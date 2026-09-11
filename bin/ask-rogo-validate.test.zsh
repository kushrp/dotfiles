#!/usr/bin/env zsh

set -u

guard=${GUARD_UNDER_TEST:-${0:A:h}/ask-rogo-validate}
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/ask-rogo-validate-test.XXXXXX")

cleanup() {
  rm -rf -- "$test_dir"
}

trap cleanup EXIT

fail() {
  print -u2 -- "FAIL: $1"
  exit 1
}

run_guard() {
  ASK_ROGO_VALIDATION_LOCK="$test_dir/validation.lock" \
    ASK_ROGO_VALIDATION_TIMEOUT="${ASK_ROGO_VALIDATION_TIMEOUT:-5s}" \
    "$guard" "$@"
}

[[ -x "$guard" ]] || fail "guard is not executable: $guard"

set +e
no_command_output=$(run_guard 2>&1)
no_command_status=$?
set -e

[[ $no_command_status -eq 64 ]] || fail "missing command returned $no_command_status"
[[ $no_command_output == *"Usage:"* ]] || fail "missing command did not show usage"

concurrency=$(run_guard zsh -c 'print -r -- "$TURBO_CONCURRENCY"') || fail "command forwarding failed"
[[ $concurrency == "1" ]] || fail "expected TURBO_CONCURRENCY=1, got $concurrency"
[[ ! -e "$test_dir/validation.lock" ]] || fail "successful run left the lock behind"

separator_output=$(run_guard -- /usr/bin/printf '%s\n' "separator works") || fail "separator invocation failed"
[[ $separator_output == "separator works" ]] || fail "separator invocation changed the command"

concurrency=$(TURBO_CONCURRENCY=8 run_guard zsh -c 'print -r -- "$TURBO_CONCURRENCY"') || fail "concurrency override check failed"
[[ $concurrency == "1" ]] || fail "inherited concurrency bypassed the guard: $concurrency"

ready_file="$test_dir/ready"
run_guard zsh -c 'touch "$1"; sleep 2' zsh "$ready_file" &
holder_pid=$!

for _ in {1..40}; do
  [[ -e "$ready_file" ]] && break
  sleep 0.05
done

[[ -e "$ready_file" ]] || fail "lock holder did not start"

set +e
contention_output=$(run_guard true 2>&1)
contention_status=$?
set -e

[[ $contention_status -eq 75 ]] || fail "contention returned $contention_status"
[[ $contention_output == *"validation is already running"* ]] || fail "contention message is unclear"
wait "$holder_pid" || fail "lock holder failed"
[[ ! -e "$test_dir/validation.lock" ]] || fail "completed holder left the lock behind"

timeout_pid_file="$test_dir/timeout-child.pid"
set +e
ASK_ROGO_VALIDATION_TIMEOUT=0.2s run_guard sh -c 'echo $$ > "$1"; sleep 10' sh "$timeout_pid_file" >/dev/null 2>&1
timeout_status=$?
set -e

[[ $timeout_status -eq 124 ]] || fail "timeout returned $timeout_status"
timeout_child_pid=$(<"$timeout_pid_file")
! kill -0 "$timeout_child_pid" 2>/dev/null || fail "timeout left child PID $timeout_child_pid running"
[[ ! -e "$test_dir/validation.lock" ]] || fail "timed-out run left the lock behind"

set +e
child_124_output=$(run_guard zsh -c 'exit 124' 2>&1)
child_124_status=$?
set -e

[[ $child_124_status -eq 124 ]] || fail "child exit 124 returned $child_124_status"
[[ $child_124_output != *"sending signal due to timeout"* ]] || fail "child exit 124 was mislabeled as a timeout"

child_pid_file="$test_dir/child.pid"
ASK_ROGO_VALIDATION_LOCK="$test_dir/validation.lock" \
  ASK_ROGO_VALIDATION_TIMEOUT=5s \
  "$guard" sh -c 'echo $$ > "$1"; sleep 30' sh "$child_pid_file" &
wrapper_pid=$!

for _ in {1..40}; do
  [[ -e "$child_pid_file" ]] && break
  sleep 0.05
done

[[ -e "$child_pid_file" ]] || fail "signal test child did not start"
child_pid=$(<"$child_pid_file")
kill -TERM "$wrapper_pid"
set +e
wait "$wrapper_pid"
signal_status=$?
set -e

[[ $signal_status -eq 143 ]] || fail "terminated wrapper returned $signal_status"
for _ in {1..40}; do
  ! kill -0 "$child_pid" 2>/dev/null && break
  sleep 0.05
done
! kill -0 "$child_pid" 2>/dev/null || fail "terminated wrapper left child PID $child_pid running"
[[ ! -e "$test_dir/validation.lock" ]] || fail "terminated wrapper left the lock behind"

print -r -- "999999" > "$test_dir/validation.lock"
set +e
stale_output=$(run_guard true 2>&1)
stale_status=$?
set -e
[[ $stale_status -eq 69 ]] || fail "stale lock returned $stale_status"
[[ $stale_output == *"stale lock"* ]] || fail "stale lock message is unclear"
[[ -e "$test_dir/validation.lock" ]] || fail "guard removed a stale lock automatically"

print -- "PASS: ask-rogo validation guard"
