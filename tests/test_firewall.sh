#!/usr/bin/env bash
# Test of the thin CLI layer msw-firewall (coarse validation, no live firewall
# state needed -- an invalid app/action is already rejected in the wrapper,
# before sudo/the privileged helper is even invoked).
#
# The app whitelist is CONFIG-DRIVEN (config.firewall.apps; default, config
# absent/empty, is rdp+vnc). This file intentionally never exercises a VALID
# app end-to-end (that mutating block/allow round-trip -- including for a
# config-driven custom app -- is covered by test_firewall_apply.sh, which
# talks to the privileged helper directly); it only exercises rejection
# paths, all of which are caught in the wrapper BEFORE any sudo call, so
# nothing here ever mutates real firewall state.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
CLI=bin/msw-firewall

assert "[ -x $CLI ]" "msw-firewall is executable"

# --- Config backup/restore (real path, same pattern as test_status_json.sh) -
CFG_DIR="$HOME/.config/mobileserverswitch"
CFG_FILE="$CFG_DIR/config.json"
CFG_BACKUP=""
if [ -e "$CFG_FILE" ]; then
    CFG_BACKUP=$(mktemp)
    cp "$CFG_FILE" "$CFG_BACKUP"
fi
restore_cfg() {
    if [ -n "$CFG_BACKUP" ]; then
        mkdir -p "$CFG_DIR"
        cp "$CFG_BACKUP" "$CFG_FILE"
        rm -f "$CFG_BACKUP"
    else
        rm -f "$CFG_FILE"
        rmdir "$CFG_DIR" 2>/dev/null || true
    fi
}
trap restore_cfg EXIT
rm -f "$CFG_FILE"   # start from "no config" (default rdp+vnc whitelist)

# --- Unknown action ----------------------------------------------------------
$CLI bogus rdp 2>/dev/null && { echo "FAIL: unknown action should have been rejected"; exit 1; }

# --- Unknown app (default whitelist: rdp, vnc; no config) --------------------
$CLI block bogus 2>/dev/null && { echo "FAIL: unknown app should have been rejected"; exit 1; }
$CLI allow bogus 2>/dev/null && { echo "FAIL: unknown app should have been rejected"; exit 1; }
$CLI block sunshine 2>/dev/null && { echo "FAIL: 'sunshine' is not in the default whitelist (no config), should have been rejected"; exit 1; }

# --- Hard refusal already at the wrapper level (no config): ssh/22/tailscale
#     are not valid apps in the whitelist -- rejected here already, before
#     the privileged helper is even reached.
for bad in ssh 22 tailscale tailscale0; do
    $CLI block "$bad" 2>/dev/null && { echo "FAIL: '$bad' is never a valid app, should have been rejected (no config)"; exit 1; }
done

# --- Missing app argument -----------------------------------------------------
$CLI block 2>/dev/null && { echo "FAIL: missing app argument should have been rejected"; exit 1; }

# --- No argument -> usage, exit 0 (like msw-power) ---------------------------
$CLI >/dev/null
assert_eq "$?" "0" "no argument -> usage, exit 0"

# --- Config-driven whitelist: with a temp config listing only "myapp", the --
#     built-in default (rdp) is no longer accepted, and the hard refusal
#     still holds. This never mutates real firewall state: every case here
#     is rejected by the wrapper's own validation before any sudo call runs.
mkdir -p "$CFG_DIR"
cat > "$CFG_FILE" <<'JSON'
{ "firewall": { "apps": [ { "id": "myapp", "ports_tcp": "9999" } ] } }
JSON

$CLI block rdp 2>/dev/null && { echo "FAIL: 'rdp' should be rejected once config.firewall.apps no longer lists it"; exit 1; }

for bad in ssh 22 tailscale tailscale0; do
    $CLI block "$bad" 2>/dev/null && { echo "FAIL: '$bad' is never a valid app, should have been rejected (config present)"; exit 1; }
done

pass
