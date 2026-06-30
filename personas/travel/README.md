# travel persona

A "persona" = a heavy tool suite kept OUT of the default agent system prompt and
loaded **only on demand** via a launcher. This one is the travel-hacker suite
(flight/hotel/award search). Default `cc` / `codex` / `opencode` stay lean
(~3.5k fewer tokens/turn); you opt in with `ct` / `cxt` / `ot`.

## Canonical files (this dir is the single source of truth)

| File | Tool | Format |
|------|------|--------|
| `travel-hacker/` | Claude | vendored plugin (44 skills + 1 agent) |
| `claude.mcp.json` | Claude | `--mcp-config` (mcpServers) |
| `codex.config.toml` | Codex | `--profile travel` layer (`[mcp_servers.*]`) |
| `opencode.json` | opencode | `OPENCODE_CONFIG` (mcp + Rogo provider mirror) |

All carry the same 8 MCP servers: skiplagged, kiwi, trivago, ferryhopper,
liteapi, airbnb, google-flights, pointsyeah. **Keep the three in sync** when
adding/removing a server.

## How it's wired (install.sh `setup_personas`)

Symlinked into each tool's expected location so the launchers find them:

```
~/.claude/personas/travel-hacker      -> personas/travel/travel-hacker
~/.claude/personas/travel.mcp.json    -> personas/travel/claude.mcp.json
~/.codex/travel.config.toml           -> personas/travel/codex.config.toml   (codex --profile needs $CODEX_HOME)
~/.config/opencode/travel.json        -> personas/travel/opencode.json
```

Launchers live in `.zshrc` §7c (`ct`/`cxt`/`ot`). Migration to a new machine =
clone dotfiles + `install.sh` (recreates the symlinks); launchers travel with `.zshrc`.

## Notes

- **Launch-time only.** The system prompt is built at startup, so "reference it"
  means running `ct`/`cxt`/`ot`, not typing "travel hacker" mid-session. Subagents
  inherit the launching session, so they get the suite automatically.
- `liteapi` needs `LITEAPI_API_KEY` in the env; `pointsyeah` was failing to connect
  when added (may need `claude mcp auth pointsyeah` / endpoint may have moved).
- opencode gets the MCP servers only — Claude-plugin skills don't port to opencode's
  skill system.
- `travel-hacker/data/` (3.8M of hotel/airport JSON) is **gitignored** (refreshable). The
  remote MCP servers don't need it; some offline-lookup skills do. On a new machine, populate
  it with `travel-hacker/scripts/refresh-hotel-data.py` / `refresh-transfer-bonuses.py`.
- To add another persona (e.g. figma, datadog): mirror this dir under
  `personas/<name>/`, add a `setup_personas` symlink block, add a `c<x>`/launcher in `.zshrc`.
