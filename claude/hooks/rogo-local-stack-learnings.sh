#!/bin/bash
# PreToolUse soft-nudge (ask-rogo only): when a Bash command touches the LOCAL-STACK
# bringup path (base seed, connector pull/load, dev services, formal/cloud-sql
# proxies, op, type-check), inject the hard-won gotchas so we don't re-trip.
#
# 2026-07-01: bringing up connectors for a felix-home dogfood took ~30 rediscovery
# steps — wrong Formal token field, the Formal proxy dying across Bash calls, a
# migrated-but-unseeded DB, agent-library not linked, op timing out. Each branch
# below is one of those trips. Full path: felix-home-local-connector-recipe +
# rogo-local-stack-bringup memories.
#
# Output: hookSpecificOutput.additionalContext; always allows. Fail-open (any
# internal error -> exit 0 silently; never block a Bash call on this nudge).
set -uo pipefail

INPUT=$(cat)
[ "$(echo "$INPUT" | jq -r '.tool_name // empty')" = "Bash" ] || exit 0
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0

# Only nudge inside an ask-rogo checkout — otherwise these are irrelevant noise.
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
case "$CWD" in *ask-rogo*) : ;; *) exit 0 ;; esac

MSG=""
if echo "$CMD" | grep -qE 'pull_dream_data|load-dream-data|DREAM_COHORT|dream-eval'; then
  MSG="Felix Home connectors (bring up locally). PREFER the no-DB-creds LOAD path (George PR #36448): from apps/backend run load-dream-data.ts with DREAM_COHORT=<cohort-YYYY-MM-DD> + GOOGLE_APPLICATION_CREDENTIALS=\$HOME/.config/gcloud/application_default_credentials.json (KMS decrypt via personal ADC -> NoOp re-encrypt); cohorts live in gs://rogo-eval-data/dream-eval/. Scope to just your user: stage kush-only user_credential.csv/tool_integration.csv in scripts/dream-eval/.local/dream-eval, guard syncCohort with 'if(!process.env.NO_SYNC)', and run NO_SYNC=1 DREAM_COHORT=<dummy>. FRESH pull (only for current tokens) uses Formal and is flaky: FORMAL_TOKEN = the 'Formal' 1Password item's *token* field (NOT 'Staging Access Token: Staging Connect Read Only'); start 'formal connect saas-staging --port 6432' as a PERSISTENT background process (a (cmd &) subshell dies when the Bash call ends -> intermittent 'server closed the connection'); run with USER=kush (identity idp:formal:human:kush@rogo.ai, since \$USER=kushrustagi); Formal pulls rogo-auth tables but DROPS on the tool-proxy connector tables. PREREQ: the load needs the base seed ('Rogo Support' org). Details: felix-home-local-connector-recipe memory."
elif echo "$CMD" | grep -qE 'prisma-seed-local|seed-tenant'; then
  MSG="Base tenant seed. A migrated-but-empty local DB (0 orgs) fails the connector load with 'Local Organization \"Rogo Support\" not found'. seed-tenant-v2 reads env it normally gets from packages/db/.env (op inject of .env.1p); if op is down, set inline: DATABASE_URL=postgres://postgres:mysecretpassword@localhost:5432/ask_rogo_local?schema=rogo-auth TENANT_APPROVED_EMAIL_DOMAINS=acme.com CUSTOMER_NAME='Bank of Acme'. Creates Bank of Acme + Rogo Support orgs (the load's required org) + your user."
elif echo "$CMD" | grep -qE 'dev:web|turbo (run )?dev|next dev|run-search-server|bun run dev|entrypoint\.ts|dev:effect-cluster'; then
  MSG="Local dev stack. 'turbo run dev:web' = backend(4004) + frontend(3000) + rogo-agent HTTP(3009) + Effect cluster(ws 3010). rogo-agent MUST have secrets first: 'cd apps/rogo-agent && op inject -i .env.1p -o .env -f' — without it .env lacks PORT=3009 so rogo-agent defaults to 3000 and crashes into the frontend, and POST /chats hangs ~60s with no error. Kill stale procs on 3000/4004/4001/3009/3010 first. The rogo-agent Effect cluster only sees new connector tokens after (re)start. BEFORE booting: verify BOTH apps/backend/.env and apps/rogo-agent/.env DATABASE_URLs point at the intended DB — parallel sessions have silently flipped them to the per-worktree TEST db (ask_rogo_<worktree>), which TestDatabaseHelper EMPTIES → login dies with 'Request access to continue' (UnauthorizedUserCreationError). Prefer a dedicated demo DB (e.g. ask_rogo_felix_demo) over shared ask_rogo_local, whose schema can be reverted under you by other worktrees while 'migrate status' still says up-to-date. Java search server (port 8080) is needed for UI tests."
elif echo "$CMD" | grep -qE 'bun run init|dev-init'; then
  MSG="Local init: the runtime is colima (the 'docker' CLI may be MISSING — only docker-compose; check 'colima status' + ports 5432/6379/9010). Tailscale MUST be connected (backend resolves GCP Secret Manager at boot). Infra may already be up + schema migrated but the DB UNSEEDED — you likely only need prisma-seed-local, not a full re-init."
elif echo "$CMD" | grep -qE 'prisma-migrate-local|migrate dev|migrate deploy|prisma migrate'; then
  MSG="DB migrations on ask_rogo_local: it's SHARED across worktrees, so its migration history often DIVERGES (a parallel felix-arena experiment left felix_arena/arena_live_lifecycle migrations the current code lacks, while the code has pending ones the DB lacks). 'prisma-migrate-local' = 'migrate dev' which will RESET (wipe seed + connectors) on a history mismatch. Use 'bunx prisma migrate deploy' instead (DATABASE_URL=postgres://postgres:mysecretpassword@localhost:5432/ask_rogo_local?schema=rogo-auth) — it only APPLIES pending migrations, never resets, transactional per-migration. That fixes the backend's 'scheduledTask column does not exist' startup crash. To render Felix Home for kush after: SET experimentalFeatures += 'felix-home' on the User row; engine access (enable:felix-lite/medium/max) already comes via the 'Default Rogo Support Team Permissions' group from seed-tenant-v2."
elif echo "$CMD" | grep -qE 'op inject|op signin|pull-env'; then
  MSG="1Password op: the session times out mid-work — re-run 'op signin' (export OP_ACCOUNT=rogotechnologiesinc.1password.com if it complains about multiple accounts). pull-env:local = op inject of apps/e2e/.env.local.1p. Backend .env is often MISSING TEST_PROVISION_SECRET (copy the value from apps/e2e/.env into apps/backend/.env and restart the backend)."
elif echo "$CMD" | grep -qE 'type-check|tsc --noEmit'; then
  MSG="If the backend type-check fails ONLY on \"Cannot find module '@rogo-technologies/agent-library'\" (or a similar new workspace pkg), that's a new-main package not linked in this worktree's node_modules — 'bun install --frozen-lockfile' links it (no lockfile churn). It's an env artifact, NOT a code failure; CI resolves it via install."
fi

[ -z "$MSG" ] && exit 0

# Append the /brain learnings index for local-run commands: static core list (works
# even when iCloud has stubbed files) + dynamic sweep of the vault's solutions dirs
# (description: lines), so new compound notes surface without editing this hook.
VAULT_SOL="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Kush's Vault/Kush's vault/04 - Resources/Compound/solutions"
BRAIN="BRAIN (recall before local ask-rogo work — brain skill, vault 04 - Resources/Compound):
- workflow-issues/run-independent-felix-stack-on-alt-ports.md — alt-port second stack + the shared-DB battleground doctrine (dedicated DB per demo/experiment; verify .env DATABASE_URLs first; migrate status up-to-date does not mean schema matches code)
- integration-issues/local-auth0-backend-owns-the-callback.md — unauthorized_user_creation decode; BACKEND/FRONTEND_BASE_URL on the backend route Auth0; bun --watch never reloads .env
- database-issues/prisma-p2022-local-migration-drift-hand-apply.md — P2022 drift hand-apply recipe
- database-issues/prisma-upsert-single-unique-never-throws-p2002.md — upsert race handlers are dead code; create+catch
- test-failures/org-scoped-seeds-two-schema-green-runs.md — seeds carry organizationId; green runs must name their schema
- workflow-issues/divergent-worktree-port-protocol.md — stale parallel worktrees: port onto the real tip, check upstream first"
if [ -d "$VAULT_SOL" ]; then
  EXTRA=$(grep -ril --include='*.md' -E 'tags:.*(local-dev|alt-ports|auth0|local-stack)' "$VAULT_SOL" 2>/dev/null | while read -r f; do
    rel=${f#"$VAULT_SOL"/}
    printf '%s' "$BRAIN" | grep -qF "$rel" && continue
    desc=$(grep -m1 '^description:' "$f" 2>/dev/null | cut -c1-160)
    printf -- '- %s — %s\n' "$rel" "${desc#description: }"
  done)
  [ -n "$EXTRA" ] && BRAIN="$BRAIN
$EXTRA"
fi
MSG="$MSG

$BRAIN"

jq -n --arg msg "$MSG" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",additionalContext:$msg}}'
exit 0
