#!/usr/bin/env python3
"""SessionStart hook (wired for the "clear" source): brief a fresh context.

After a handoff-triggered /clear, find the handoff doc that best matches this
session and inject it into the new context. Candidates come from three places,
deduped by realpath and scored by how well they match the current session:

  1. the repo-local handoff store resolved from the current cwd. Every worktree
     of a repo shares ONE store (git --git-common-dir collapses them), so this
     glob returns handoffs from sibling worktrees too. We therefore do NOT trust
     "it's in our store" as ownership — each doc is scored by its writer's
     recorded session/worktree (looked up in the global index by the doc's
     <session_id>.md stem), exactly like a global-pointer candidate;
  2. the global pointer index (~/.claude/handoff-index), so a handoff written
     in one cwd is found when /clear runs from a different one — e.g. you worked
     inside a repo worktree but cleared from a parent directory, or you're
     resuming another session's handoff. Each pointer records the writer's true
     session_id/cwd/repo/worktree (see handoff-threshold-stop.py), so matching
     never depends on the model's prose;
  3. the OS temp dir, because the `handoff` skill's own default is to save
     there.

Match score (higher wins; ties break to newest):
  120  same session id (a true resume of the writer's own session)
  110  same worktree (this session's `git --show-toplevel` == writer's)
  100  same cwd as the writer
   90  same repo, DIFFERENT worktree — recorded but BELOW the auto-load bar;
        surfaced as an explicit option, never silently loaded for you
   70  doc body names this session's cwd/repo (content marker)
   60  content-marked temp doc
   50  ancestor/descendant cwd (e.g. cleared from a parent dir)
A real signal is required (>= MIN_SCORE) to auto-load; an unrelated handoff is
never loaded. Fuzzy matches (< 60) are bounded to a tighter recency window so a
stale handoff from an unrelated session is not pulled into a generic parent-dir
/clear.

Disambiguate-on-tie: if more than one candidate clears MIN_SCORE and they do
not share this session/worktree, nothing is auto-loaded — instead the candidates
(path, title, mtime) are listed and the user is told to load one by path. A
single clear winner still auto-loads.

Consume-once: the loaded doc is renamed to *.loaded, its global pointer and any
now-dangling pointers are removed, and stale .pending-* markers are cleared, so
re-clearing later does not re-inject an outdated handoff.

Pairs with handoff-threshold-stop.py.
"""
import glob
import json
import os
import subprocess
import sys
import tempfile
import time

MAX_AGE_S = 2 * 86400
FUZZY_MAX_AGE_S = 18 * 3600
MIN_SCORE = 50

# Scores at/above this bar mean "this session's own work" and may auto-load.
# Same-repo-different-worktree (SCORE_SAME_REPO) sits below it: recorded and
# offered as an explicit option, never silently loaded into the wrong worktree.
SCORE_SAME_SESSION = 120
SCORE_SAME_WORKTREE = 110
SCORE_SAME_CWD = 100
SCORE_SAME_REPO = 90
AUTO_LOAD_BAR = SCORE_SAME_CWD

GLOBAL_INDEX = os.path.expanduser("~/.claude/handoff-index")


def git_common_root(cwd: str):
    """The repo root shared across all worktrees, or None. Mirrors the writer."""
    try:
        out = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--git-common-dir"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        common = out.stdout.strip()
        if out.returncode == 0 and common:
            common = os.path.abspath(os.path.join(cwd, common))
            return os.path.dirname(common)
    except Exception:
        pass
    return None


def git_worktree_root(cwd: str):
    """This worktree's own root, or None. Mirrors the writer.

    --show-toplevel does NOT collapse linked worktrees the way --git-common-dir
    does, so it distinguishes two sessions in two worktrees of the same repo.
    """
    try:
        out = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        top = out.stdout.strip()
        if out.returncode == 0 and top:
            return os.path.abspath(top)
    except Exception:
        pass
    return None


def resolve_handoff_dir(cwd: str) -> str:
    root = git_common_root(cwd)
    base = root if root else cwd
    return os.path.join(base, ".claude", "handoffs")


def is_within(child: str, parent: str) -> bool:
    """True if `child` is `parent` or nested under it."""
    try:
        child = os.path.abspath(child)
        parent = os.path.abspath(parent)
        return os.path.commonpath([child, parent]) == parent
    except ValueError:
        return False  # different drives / relative-vs-absolute mismatch


def body_mentions(doc: str, marks: list) -> bool:
    if not marks:
        return False
    try:
        with open(doc) as f:
            body = f.read()
    except OSError:
        return False
    return any(mark in body for mark in marks)


def temp_handoff_docs(markers: list) -> list:
    """Recent *handoff*.md files in the OS temp dir(s) that reference this repo.

    Two guards keep temp (shared and repo-agnostic) from cross-contaminating
    repos: mtime recency, and a content check that the doc references one of
    `markers` (the repo root or cwd).
    """
    seen_dirs = set()
    cutoff = time.time() - MAX_AGE_S
    found = []
    for d in (os.environ.get("TMPDIR"), tempfile.gettempdir(), "/tmp"):
        if not d or d in seen_dirs:
            continue
        seen_dirs.add(d)
        for path in glob.glob(os.path.join(d, "*[Hh]andoff*.md")):
            try:
                if os.path.getmtime(path) < cutoff:
                    continue
            except OSError:
                continue
            if body_mentions(path, markers):
                found.append(path)
    return found


def score_pointer(
    ptr: dict,
    cwd: str,
    repo_root,
    doc: str,
    marks: list,
    session_id=None,
    worktree=None,
) -> int:
    """Score a candidate doc by how well its writer's recorded identity matches
    this session. Session and worktree identity are authoritative; cwd/repo/body
    are fallbacks. Same-repo-different-worktree returns SCORE_SAME_REPO, which is
    below the auto-load bar so it is offered, not silently loaded.

    A missing/empty pointer (no recorded identity) yields a body/cwd fallback at
    most, never a session/worktree match — so unknown docs stay below the bar.
    """
    if not isinstance(ptr, dict):
        ptr = {}

    def _str(v):
        return v if isinstance(v, str) and v else None

    p_session = _str(ptr.get("session_id"))
    p_cwd = _str(ptr.get("cwd"))
    p_root = _str(ptr.get("repo_root"))
    p_worktree = _str(ptr.get("worktree"))

    if session_id and p_session and p_session == session_id:
        return SCORE_SAME_SESSION
    if worktree and p_worktree and os.path.abspath(p_worktree) == worktree:
        return SCORE_SAME_WORKTREE
    if p_cwd and os.path.abspath(p_cwd) == cwd:
        return SCORE_SAME_CWD
    if repo_root and p_root and os.path.abspath(p_root) == repo_root:
        return SCORE_SAME_REPO
    score = 0
    if body_mentions(doc, marks):
        score = max(score, 70)
    if p_cwd and (is_within(p_cwd, cwd) or is_within(cwd, p_cwd)):
        score = max(score, 50)
    return score


def load_pointer_index() -> dict:
    """Map session_id -> pointer dict for every readable pointer in the global
    index. Used to score repo-local docs by their <session_id>.md stem."""
    index = {}
    for ptr_path in glob.glob(os.path.join(GLOBAL_INDEX, "*.json")):
        try:
            with open(ptr_path) as f:
                ptr = json.load(f)
        except (OSError, json.JSONDecodeError):
            continue
        if isinstance(ptr, dict):
            sid = ptr.get("session_id") or os.path.splitext(os.path.basename(ptr_path))[0]
            index[sid] = ptr
    return index


def gather_candidates(cwd: str, session_id=None) -> list:
    """Return [{doc, score, mtime}] for handoffs relevant to this session,
    best first. Deduped by realpath, recency-bounded per match strength.

    Repo-local docs are NOT auto-trusted: every worktree shares one store, so
    each repo-local doc is scored by its writer's recorded identity (looked up
    by the doc's <session_id>.md stem) against this session's id/worktree/cwd —
    the same scoring used for global pointers. A repo-local doc with no pointer,
    or whose pointer points elsewhere, scores below the auto-load bar."""
    cwd = os.path.abspath(cwd)
    repo_root = git_common_root(cwd)
    worktree = git_worktree_root(cwd)
    marks = [m for m in (cwd, repo_root, repo_root and os.path.basename(repo_root)) if m]
    now = time.time()
    pointer_index = load_pointer_index()
    best = {}

    def consider(doc: str, score: int, ptr: dict) -> None:
        if score < MIN_SCORE or not doc or not os.path.exists(doc):
            return
        try:
            mtime = os.path.getmtime(doc)
        except OSError:
            return
        age_limit = MAX_AGE_S if score >= 60 else FUZZY_MAX_AGE_S
        if now - mtime > age_limit:
            return
        rp = os.path.realpath(doc)
        prev = best.get(rp)
        if prev is None or (score, mtime) > (prev["score"], prev["mtime"]):
            best[rp] = {
                "doc": doc,
                "score": score,
                "mtime": mtime,
                # Writer identity so select() can tell same-worktree ties (pick
                # newest) from cross-worktree ambiguity (refuse, disambiguate).
                "writer_worktree": (ptr or {}).get("worktree"),
                "writer_session": (ptr or {}).get("session_id"),
            }

    # 1. Repo/cwd store (shared across worktrees). Score each doc by its writer's
    #    recorded identity — the stem is the writer session_id, so look it up.
    for doc in glob.glob(os.path.join(resolve_handoff_dir(cwd), "*.md")):
        stem = os.path.splitext(os.path.basename(doc))[0]
        ptr = pointer_index.get(stem, {})
        consider(doc, score_pointer(ptr, cwd, repo_root, doc, marks, session_id, worktree), ptr)

    # 2. Global pointers from any session.
    for sid, ptr in pointer_index.items():
        doc = ptr.get("doc_path")
        if doc:
            consider(doc, score_pointer(ptr, cwd, repo_root, doc, marks, session_id, worktree), ptr)

    # 3. Temp dir (handoff skill default), content-marked to this repo.
    for doc in temp_handoff_docs(marks):
        consider(doc, 60, {})

    return sorted(best.values(), key=lambda c: (c["score"], c["mtime"]), reverse=True)


def consume(doc: str) -> None:
    """Mark a loaded handoff consumed and clean up stale index/markers."""
    try:
        os.rename(doc, doc + ".loaded")
    except OSError:
        pass
    for ptr_path in glob.glob(os.path.join(GLOBAL_INDEX, "*.json")):
        try:
            with open(ptr_path) as f:
                dp = json.load(f).get("doc_path")
        except (OSError, json.JSONDecodeError):
            continue
        if dp == doc or (dp and not os.path.exists(dp)):
            try:
                os.remove(ptr_path)
            except OSError:
                pass
    for stale in glob.glob(os.path.join(os.path.dirname(doc), ".pending-*")):
        try:
            os.remove(stale)
        except OSError:
            pass


def doc_title(doc: str) -> str:
    """First Markdown heading line, or the basename if none/unreadable."""
    try:
        with open(doc) as f:
            for line in f:
                line = line.strip()
                if line.startswith("#"):
                    return line.lstrip("#").strip() or os.path.basename(doc)
    except OSError:
        pass
    return os.path.basename(doc)


def select(candidates: list) -> dict:
    """Decide what to do with scored candidates (best-first). Returns:
      {"action": "none"}                              nothing to load
      {"action": "load", "doc": <path>}               single clear winner
      {"action": "disambiguate", "candidates": [...]} ambiguous; let user pick

    Auto-load requires a candidate that is THIS session's own work — score at or
    above AUTO_LOAD_BAR (same session, same worktree, or same cwd). Among such
    candidates, a tie breaks to newest mtime ONLY when they all share one
    worktree/session; if they span different worktrees we refuse and list them.

    Anything BELOW the bar (same-repo-different-worktree, body mention, fuzzy
    ancestor) is never silently loaded: a single below-bar match could be an
    unrelated handoff whose body merely names a shared path, so it is surfaced
    for the user to confirm rather than guessed. This is the cross-worktree
    feature, exposed only as an explicit, listed option.
    """
    if not candidates:
        return {"action": "none"}

    ours = [c for c in candidates if c["score"] >= AUTO_LOAD_BAR]
    if ours:
        worktrees = {c.get("writer_worktree") for c in ours}
        sessions = {c.get("writer_session") for c in ours}
        # One clear owner: a single doc, or several all from the same worktree
        # (or same session) — pick the newest, which is best-first already.
        same_owner = len(ours) == 1 or (
            len(worktrees) == 1 and None not in worktrees
        ) or (len(sessions) == 1 and None not in sessions)
        if same_owner:
            return {"action": "load", "doc": ours[0]["doc"]}
        # Multiple owners cleared the bar but belong to different worktrees →
        # do not guess; let the user pick.
        return {"action": "disambiguate", "candidates": ours}

    # Nothing is clearly this session's own work. Below-bar signals (same-repo
    # other worktree, body mention) are real but ambiguous → offer, never load.
    offerable = [c for c in candidates if c["score"] >= MIN_SCORE]
    if not offerable:
        return {"action": "none"}
    return {"action": "disambiguate", "candidates": offerable}


def disambiguation_message(candidates: list) -> str:
    if len(candidates) == 1:
        head = (
            "A handoff document might match this session, but it is not clearly "
            "this session's own work (it could belong to another worktree, or "
            "its body merely names a shared path) — so it was not loaded "
            "automatically. If it is yours, read it by its exact path:"
        )
    else:
        head = (
            "Multiple handoff documents could match this session, and they are "
            "not all from the same session/worktree — so nothing was loaded "
            "automatically (loading the wrong one would brief you on unrelated "
            "work). Read the one that matches your thread by its exact path:"
        )
    lines = [head, ""]
    for c in candidates:
        doc = c["doc"]
        when = time.strftime("%Y-%m-%d %H:%M", time.localtime(c["mtime"]))
        lines.append(f"- `{doc}`")
        lines.append(f"    {doc_title(doc)} (modified {when})")
    lines.append("")
    lines.append("Tell me which path to read, then I'll pick up from there.")
    return "\n".join(lines)


def emit_context(context: str) -> None:
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "SessionStart",
                    "additionalContext": context,
                }
            }
        )
    )


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0  # fail safe: no valid input → behave as if nothing to load
    cwd = data.get("cwd") or os.getcwd()
    session_id = data.get("session_id")

    candidates = gather_candidates(cwd, session_id)
    decision = select(candidates)

    if decision["action"] == "none":
        return 0

    if decision["action"] == "disambiguate":
        emit_context(disambiguation_message(decision["candidates"]))
        return 0

    newest = decision["doc"]
    with open(newest) as f:
        content = f.read()

    context = (
        f"A previous session handed off its context. It crossed the token "
        f"threshold, summarized its state into `{os.path.basename(newest)}`, "
        f"and cleared. Pick up exactly where it left off.\n\n"
        f"---\n\n{content}"
    )

    consume(newest)
    emit_context(context)
    return 0


if __name__ == "__main__":
    # Fail safe: any unexpected error must degrade to "load nothing", never
    # crash SessionStart for every one of Kush's concurrent sessions.
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)
