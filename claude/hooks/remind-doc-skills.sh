#!/bin/bash
# PreToolUse soft-nudge: remind Claude to load doc-craft (and finish with humanizer)
# before writing doc prose. Fires on Notion content writes and on Write/Edit into
# the Obsidian vault's doc folders. Editing an existing doc counts as doc writing —
# that's the exact miss this hook exists to prevent (2026-06-12: Notion doc updates
# went out without the skill loaded).
# Output: hookSpecificOutput.additionalContext; the tool call always proceeds.

# Fail-open: never block tool calls. Any internal error → exit 0 silently.
set -uo pipefail

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

NUDGE=no
case "$TOOL_NAME" in
  mcp__notion__notion-create-pages)
    NUDGE=yes
    ;;
  mcp__notion__notion-update-page)
    # Only content-bearing commands; property/icon updates aren't prose.
    CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
    case "$CMD" in
      update_content|replace_content|insert_content) NUDGE=yes ;;
    esac
    ;;
  Write|Edit|MultiEdit)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    case "$FILE_PATH" in
      *"Kush's vault"*.md) NUDGE=yes ;;
    esac
    ;;
esac

if [ "$NUDGE" = "yes" ]; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      additionalContext: "Doc writing detected (Notion page content or a vault note). Editing an existing doc counts as doc writing. If you have not already done so this session: load the doc-craft skill BEFORE composing the prose, and apply the humanizer pass (no em-dashes, no semicolons in Notion prose, plain words, no AI-writing tells) before submitting. If both are already loaded and applied this session, proceed."
    }
  }'
fi

exit 0
