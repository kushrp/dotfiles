---
date: 2026-06-25
topic: agent-fleet-ui
focus: improve UI/functionality for managing a fleet of parallel Claude Code agents in tmux + Ghostty
mode: repo-grounded
---

# Ideation: tmux/Ghostty Agent-Fleet UI

## Grounding Context (Codebase)
tmux 3.6 + Ghostty on macOS (dotfiles repo), Tokyo Night. Current stack: 2-line top status bar
(session pill; centered window tabs with agent-state glyphs, amber when waiting; right "captain's
readout" = waiting-session names + oldest-wait age + cpu/ram; line 2 = blocked-agents queue
longest-first via cc-queue). cc-dashboard (prefix a) = fzf popup of every agent pane across
sessions, sorted by longest wait, live preview (git status + last 40 lines), jump/kill/lazygit/
new/refresh. cc-status.sh Claude hooks set per-pane working/waiting/done + @cc_waiting_since +
terminal-notifier desktop notification. sesh jumper, extrakto, action menu. Worktree per agent
via `claude --worktree`. allow-passthrough on. Cohesive Tokyo Night across bat/delta/lazygit/fzf.

Known gaps: cannot judge agent output (diff) without attaching; no diff-stat; no fleet rate-limit
awareness; desktop-only notifications; no broadcast/bulk action; manual worktree cleanup/merge;
state detection relies on Claude hooks only (no Codex/aider fallback); agent activity not logged
durably.

## Topic Axes
A. Fleet observability (passive readout: status bar, glyphs, header)
B. Dashboard / triage surface (inspect, judge, act on one agent)
C. Attention routing (how the agent needing you pulls you, across devices)
D. Fleet control / bulk actions (spawn, broadcast, kill, merge across many)
E. Worktree & lifecycle (creation, naming, isolation, cleanup, merge)

## Ranked Ideas

### 1. Phone-push escalation dispatcher
**Description:** Refactor cc-status.sh's notifier into one dispatch function fanning out to
terminal-notifier AND a phone channel (ntfy/Telegram/etc.). Escalation ladder: silent in queue for
trivial waits, desktop normally, phone push once oldest-wait crosses a threshold, with batching.
**Axis:** C
**Basis:** external: ntfy.sh push-from-hook; NOC tiered on-call escalation.
**Rationale:** A blocked agent costs ~nothing at the desk but burns 20 min when you're away; this
closes the away-from-desk gap and is nearly free (hook path already computes the data).
**Downsides:** needs a phone channel set up; throttle policy needs tuning.
**Confidence:** 90%  **Complexity:** Low  **Status:** Explored (building)

### 2. Diff-aware triage in the dashboard
**Description:** +N/-M diff-stat per dashboard row; preview toggle to a delta-rendered git diff of
the worktree; single-key approve(merge)/reject(reset). Optionally order by blast-radius, not just
wait-age.
**Axis:** B
**Basis:** external: claude-squad diff tab, uzi diff stats; direct: top known gap (can't judge
output without attaching).
**Rationale:** The point of a fleet is parallel output you can rapidly accept or kill; today that
means context-switching into every pane.
**Downsides:** diff compute per render (cache by HEAD); merge needs guardrails.
**Confidence:** 88%  **Complexity:** Medium  **Status:** Unexplored

### 3. Worktree lifecycle: checkpoint + auto-reap + isolation
**Description:** A `finish` action that merges (or gt submit) + prunes worktree + clears state
atomically; auto-reap clean done worktrees on Stop hook; on spawn give each worktree a hashed dev
port + auto-copy .env via Claude's .worktreeinclude.
**Axis:** E
**Basis:** external: uzi checkpoint, worktrunk hash_port + atomic merge, agent-worktree state
machine; direct: "ask-rogo worktrees share one local DB" pain.
**Rationale:** Worktree sprawl is the silent tax that caps how many agents you'll spawn.
**Downsides:** merge automation needs a clean-only gate; Graphite interplay.
**Confidence:** 85%  **Complexity:** Medium  **Status:** Unexplored

### 4. Fleet activity log as appreciating substrate
**Description:** Wire all Claude hooks to append structured JSONL + SQLite events; status bar,
tools/min sparkline, rate-limit accounting (#6), and session replay become reads over one log.
**Axis:** A
**Basis:** external: disler multi-agent-observability; reasoned; matches user's "appreciating
substrate" principle.
**Rationale:** Keystone — every other observability feature stops re-deriving state and queries one
typed log; becomes a dataset of what agents actually do.
**Downsides:** value is second-order (infra before payoff).
**Confidence:** 82%  **Complexity:** Medium  **Status:** Unexplored

### 5. Agent-agnostic + stalled detection
**Description:** Low-frequency capture-pane scanner infers state for non-Claude agents and flags
"working but pane unchanged for N s" as a distinct stalled state. Hooks stay the fast path.
**Axis:** A
**Basis:** external: primeline 6-state capture-pane + adaptive heartbeat; direct: hooks-only gap.
**Rationale:** The worst failure is an agent silently dead but reading as alive; you only notice on
attach.
**Downsides:** heuristic misclassification; per-tool prompt patterns.
**Confidence:** 80%  **Complexity:** Medium  **Status:** Unexplored

### 6. Fleet rate-limit / quota pill
**Description:** Captain's-readout pill showing shared-account headroom + reset countdown; tint
rate-limited agents distinctly from "waiting on you"; optional auto-throttle.
**Axis:** A
**Basis:** external: amux rate-limit pill; direct: no fleet rate-limit awareness.
**Rationale:** With many agents on one account the binding constraint is the shared quota; a waiting
glyph that really means "rate-limited" sends you chasing a non-problem.
**Downsides:** sourcing live usage is the open question; best built on #4.
**Confidence:** 72%  **Complexity:** Medium  **Status:** Unexplored

### 7. Broadcast + bulk actions
**Description:** Pane-selector primitive (all / waiting-only / tagged / RTS control-group bind) +
broadcast input + bulk kill/merge, always with a confirm-preview of targets.
**Axis:** D
**Basis:** external: uzi broadcast, amux, RTS control groups.
**Rationale:** When the same nudge applies to many agents, typing it 12 times is pure toil.
**Downsides:** real danger surface; confirm-preview mandatory.
**Confidence:** 75%  **Complexity:** Low-Medium  **Status:** Unexplored

## Rejection Summary
| Idea | Reason Rejected |
|---|---|
| Meta-agent triage layer (auto-answer trivial waits) | High complexity + trust risk; better as a later brainstorm |
| Single-agent "cockpit" layout | Scope: about the solo case, not fleet management |
| Voice captain (no keybindings) | Niche; away-from-desk better served by #1 |
| 3-monitor wall / always-on ambient dashboard | Setup/taste-dependent; popup already works |
| Inter-agent collision detection (ATC handoffs) | Worktree-per-agent already isolates; rare for solo dev |
| Andon auto-halt (pause siblings on red tests) | Aggressive auto-pause risks more disruption than value |
| Orchestra "about to need you" pre-cue | Predicting imminent blocks is unreliable |
| Task-kanban reframe (unit = task not pane) | Big model change; better as a brainstorm seed |
| Standalone replay / sparkline / diff-stat-in-bar | Folded into #4 and #2 |
