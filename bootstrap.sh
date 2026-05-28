#!/usr/bin/env bash
# Backwards-compatible shim. Original upstream entrypoint was bootstrap.sh;
# new entrypoint is install.sh, which is OS-aware and idempotent.
exec "$(dirname "${BASH_SOURCE[0]}")/install.sh" "$@"
