#!/usr/bin/env bash
# Test of the thin CLI layer msw-firewall (coarse validation, no live firewall
# state needed -- an invalid app/action is already rejected in the wrapper,
# before sudo/the privileged helper is even invoked).
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
CLI=bin/msw-firewall

assert "[ -x $CLI ]" "msw-firewall is executable"

# --- Unknown action ----------------------------------------------------------
$CLI bogus rdp 2>/dev/null && { echo "FAIL: unknown action should have been rejected"; exit 1; }

# --- Unknown app (wrapper whitelist) -----------------------------------------
$CLI block bogus 2>/dev/null && { echo "FAIL: unknown app should have been rejected"; exit 1; }
$CLI allow bogus 2>/dev/null && { echo "FAIL: unknown app should have been rejected"; exit 1; }

# --- Hard refusal already at the wrapper level: ssh/22 are not valid apps in
#     the whitelist -- so they are rejected here already, not only in the
#     privileged helper.
$CLI block ssh 2>/dev/null && { echo "FAIL: 'ssh' is not a valid app, should have been rejected"; exit 1; }
$CLI block 22 2>/dev/null && { echo "FAIL: '22' is not a valid app, should have been rejected"; exit 1; }

# --- Missing app argument -----------------------------------------------------
$CLI block 2>/dev/null && { echo "FAIL: missing app argument should have been rejected"; exit 1; }

# --- No argument -> usage, exit 0 (like msw-power) ---------------------------
$CLI >/dev/null
assert_eq "$?" "0" "no argument -> usage, exit 0"

pass
