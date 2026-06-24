# tmux fluid + aesthetic redesign

**Date:** 2026-06-23
**Branch:** `tmux-fluid-redesign`
**Goal:** Make the tmux stack as fluid and aesthetic as Kun Chen's agentic workflow
(YouTube `iQyg-KypKAA`), starting with the bar at the top. Enhance the existing
Tokyo Night config — do **not** rebuild it.

## Context / decisions

- **Terminal stays Ghostty, theme stays Tokyo Night.** WezTerm's wins (Windows
  parity, Lua scripting, built-in multiplexing) are dead weight for a macOS-only,
  tmux-driven workflow. No terminal migration.
- The video deliberately skips tmux config detail, so there's no recipe to copy —
  the tmux takeaway is *bar-at-top + clean agent-state readout*, which this config
  already has 90% of. The genuine gains here are **polish + flow**.
- Workflow tooling from the video (Treehouse, First Mate, No Mistakes, voice) is
  out of scope — not tmux.conf. The worktree analog already exists as `cc <name>`.

## Findings that shape the design

- Ghostty font is **JetBrainsMono Nerd Font** → powerline separators ( `` `` )
  and nerd glyphs render correctly.
- **Cohesion seam:** Ghostty background is `#16161e` (true black), but the tmux
  bar paints `#1a1b26`. The bar sits on a different black than the terminal.
- **`sesh` + `fzf` + `zoxide` + `fd` are all installed**, and `sesh` is unused in
  tmux. Biggest available flow win.

## Changes (all in `.tmux.conf` unless noted)

### A. Bar to the top
- `status-position bottom` → `top`. (line ~145)
- The agent tally / per-window state now reads top-left → the at-a-glance
  "which agent needs me" target, matching the video's usage.

### B. Aesthetic refresh + cohesion
- Repaint the bar's base black `#1a1b26` → `#16161e` everywhere (status-style,
  every segment `bg`, window-status backgrounds) so the bar melts into the
  terminal. Accent palette (blue `#7aa2f7`, cyan `#7dcfff`, amber `#e0af68`)
  unchanged.
- Session pill and current-window tab become **rounded powerline pills** using
  `` (U+E0B6) / `` (U+E0B4) caps instead of today's colored-space edges.
- Tighten spacing on status-left / status-right.

### C. Session/window flow (headline win)
- New binding **`prefix s`** → `display-popup` running `sesh connect` over an
  `fzf` list (sessions + zoxide dirs + worktrees). Instant fuzzy jump.
- Native `choose-tree` stays available at **`prefix S`** as the fallback.
- No other keys change.

### D. Louder "waiting" tab
- An inactive window whose `@cc_win == waiting` renders its tab in amber
  (`#e0af68`) instead of dim (`#565f89`), so a crew member needing input is
  unmissable from the top bar. Implemented via a color-only `#{?}` token embedded
  in the style (follows the existing "no commas inside conditionals" rule).
- The ◆/▸/✓ rollup glyphs are kept as-is (width-safe, already working).

### E. Terminal layer
- No Ghostty change needed — its bg is already `#16161e`; cohesion is achieved by
  moving tmux to match it (B).

## Verification

- `tmux source-file ~/.tmux.conf` (via `prefix r`) with **no parse errors**.
- `tmux show-options -g status-position` → `top`.
- Confirm `${VAR}`-style format expansion still resolves (mirrors the existing
  `CC_ICON` idiom); inline the value if it doesn't.
- Visual check: bar at top, rounded pills, no color seam against the terminal,
  `prefix s` opens the sesh popup and connecting switches the client.
- Reload is non-destructive and fully revertable (`git checkout .tmux.conf`).

## Out of scope (noted, not built)
- Treehouse / First Mate / No Mistakes / voice input.
- Optional later: a `prefix Space` `display-menu` of common actions for
  discoverability.
