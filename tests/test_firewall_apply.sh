#!/usr/bin/env bash
# Live test of the firewall helper (msw-firewall-apply). Transiently mutates
# only the LAN zone's app ports -- for the default apps (rdp, vnc) and for
# temporary test-only app ids added via a temp config -- and restores the
# original state at the end -- NEVER touches ssh/22/tailscale/tailscale0, so
# it has no effect on the running SSH session or on Tailnet access (that's
# bound to tailscale0, not to the zone).
#
# The app whitelist is CONFIG-DRIVEN (config.firewall.apps); default
# (config absent/empty) is exactly rdp+vnc. This test exercises both the
# default (no config) whitelist and a temp custom config, and re-asserts the
# UNCONDITIONAL safety guards (ssh/22/tailscale hard refusal, port-22 guard
# on config-derived ports) in both states.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
HELP=/usr/local/sbin/msw-firewall-apply
ZONE=$(firewall-cmd --get-default-zone 2>/dev/null)

assert "[ -x $HELP ]" "msw-firewall-apply is executable (deployed under /usr/local/sbin)"
assert "[ -n \"$ZONE\" ]" "firewall-cmd --get-default-zone returned a zone (firewalld active)"

rich() { firewall-cmd --zone="$ZONE" --list-rich-rules 2>/dev/null; }
marker() { rich | grep -qF "$1" && echo yes || echo no; }   # $1 = literal substring
before=$(rich)

# --- Config backup/restore: this test writes/removes the REAL config path,
#     ~/.config/mobileserverswitch/config.json (same pattern as
#     test_status_json.sh) -- back up any pre-existing config and restore it
#     (or remove the temp dir/file) on exit, whether the test passes or an
#     assert exits early.
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
rm -f "$CFG_FILE"   # start clean: the default-whitelist tests below need "no config"

# --- Unknown app (no config): must fail, rich-rules unchanged ---------------
sudo -n "$HELP" block bogus 2>/dev/null && { echo "FAIL: block bogus should have failed"; exit 1; }
assert_eq "$(rich)" "$before" "block bogus (no config) did not change rich-rules"

# --- sunshine/comfyui are NOT in the built-in default whitelist anymore -----
sudo -n "$HELP" block sunshine 2>/dev/null && { echo "FAIL: 'sunshine' must be refused without a config entry (no longer a built-in default app)"; exit 1; }
assert_eq "$(rich)" "$before" "block sunshine (no config) did not change rich-rules (unknown app)"

# --- Hard refusal (no config present) -- most important security test ------
for bad in ssh 22 tailscale tailscale0; do
    sudo -n "$HELP" block "$bad" 2>/dev/null && { echo "FAIL: block $bad should have failed (hard refusal, no config)"; exit 1; }
    assert_eq "$(rich)" "$before" "block $bad (no config) did not change rich-rules"
done

# --- Default whitelist (no config): rdp -- block -> marker, idempotent, ----
#     allow -> marker gone
sudo -n "$HELP" block rdp >/dev/null
assert_eq "$(marker 'port="3389"')" "yes" "rdp block (default, no config): marker present"
sudo -n "$HELP" block rdp >/dev/null   # idempotent: no error, no duplicate entry
assert_eq "$(marker 'port="3389"')" "yes" "rdp block again: marker still present (idempotent)"
n=$(rich | grep -cF 'port="3389"')
assert_eq "$n" "1" "rdp: exactly one rule (no duplicate after second block)"
sudo -n "$HELP" allow rdp >/dev/null
assert_eq "$(marker 'port="3389"')" "no" "rdp allow: marker gone again"

# --- Default whitelist (no config): vnc -- block -> marker, allow -> gone --
sudo -n "$HELP" block vnc >/dev/null
assert_eq "$(marker 'port="5900-5903"')" "yes" "vnc block (default, no config): marker present"
sudo -n "$HELP" allow vnc >/dev/null
assert_eq "$(marker 'port="5900-5903"')" "no" "vnc allow: marker gone again"

# --- Config-driven custom app whitelist --------------------------------------
# Includes a config entry that tries to (mis)define "ssh" as an app id, to
# prove the hard refusal holds even against a config that attempts it, and
# "badapp" whose ports_tcp deliberately spans port 22 (must be refused by the
# port-22 guard -- the guard runs on config-derived ports exactly like on
# built-in ones).
mkdir -p "$CFG_DIR"
cat > "$CFG_FILE" <<'JSON'
{
  "firewall": {
    "apps": [
      { "id": "ssh",    "ports_tcp": "12345" },
      { "id": "myapp",  "ports_tcp": "9999" },
      { "id": "badapp", "ports_tcp": "20-25" }
    ]
  }
}
JSON

# --- Hard refusal STILL holds with a config present (including one that ----
#     tries to list "ssh" as an app id) ---------------------------------------
for bad in ssh 22 tailscale tailscale0; do
    sudo -n "$HELP" block "$bad" 2>/dev/null && { echo "FAIL: block $bad should have failed (hard refusal, WITH config present)"; exit 1; }
    assert_eq "$(rich)" "$before" "block $bad (with config) did not change rich-rules"
done

# --- rdp is no longer in the whitelist once a config defines its own apps --
sudo -n "$HELP" block rdp 2>/dev/null && { echo "FAIL: 'rdp' should be refused once config.firewall.apps no longer lists it"; exit 1; }
assert_eq "$(rich)" "$before" "block rdp (config present, rdp not listed) did not change rich-rules"

# --- Custom app "myapp": block -> marker present, allow -> marker gone -----
sudo -n "$HELP" block myapp >/dev/null
assert_eq "$(marker 'port="9999"')" "yes" "myapp (config-driven) block: marker present"
sudo -n "$HELP" allow myapp >/dev/null
assert_eq "$(marker 'port="9999"')" "no" "myapp (config-driven) allow: marker gone again"

# --- Custom app "badapp" (ports_tcp "20-25" spans port 22): guard refuses --
sudo -n "$HELP" block badapp 2>/dev/null && { echo "FAIL: 'badapp' (ports 20-25, spans 22) should have been refused by the port-22 guard"; exit 1; }
assert_eq "$(rich)" "$before" "block badapp (config-derived ports spanning 22) did not change rich-rules"

# --- Final state: rich-rules match pre-test state (config restored by trap) -
after=$(rich)
assert_eq "$after" "$before" "final state: rich-rules match pre-test state (no leftover reject)"

pass
