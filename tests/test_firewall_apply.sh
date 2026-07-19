#!/usr/bin/env bash
# Live test of the firewall helper (msw-firewall-apply). Transiently mutates
# only the LAN zone's app ports (rdp/vnc/sunshine/comfyui) and restores the
# original state at the end -- NEVER touches ssh/22/tailscale/tailscale0, so
# it has no effect on the running SSH session or on RDP/Sunshine over the
# Tailnet (that's bound to tailscale0, not to the zone).
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
HELP=/usr/local/sbin/msw-firewall-apply
ZONE=FedoraWorkstation

assert "[ -x $HELP ]" "msw-firewall-apply is executable (deployed under /usr/local/sbin)"

rich() { firewall-cmd --zone="$ZONE" --list-rich-rules 2>/dev/null; }
marker() { rich | grep -qE "$1" && echo yes || echo no; }   # $1 = grep -E pattern
before=$(rich)

# --- Unknown app: must fail, rich-rules unchanged ---------------------------
sudo -n "$HELP" block bogus 2>/dev/null && { echo "FAIL: block bogus should have failed"; exit 1; }
assert_eq "$(rich)" "$before" "block bogus did not change rich-rules"

# --- Hard refusal: ssh/22 (most important security test) -------------------
sudo -n "$HELP" block ssh 2>/dev/null && { echo "FAIL: block ssh should have failed (hard refusal)"; exit 1; }
assert_eq "$(rich)" "$before" "block ssh did not change rich-rules"
sudo -n "$HELP" block 22 2>/dev/null && { echo "FAIL: block 22 should have failed (hard refusal)"; exit 1; }
assert_eq "$(rich)" "$before" "block 22 did not change rich-rules"

# --- rdp: block -> marker present, idempotent, allow -> marker gone ---------
sudo -n "$HELP" block rdp >/dev/null
assert_eq "$(marker 'port="3389".*reject')" "yes" "rdp block: marker port=\"3389\"+reject present"
sudo -n "$HELP" block rdp >/dev/null   # idempotent: no error, no duplicate entry
assert_eq "$(marker 'port="3389".*reject')" "yes" "rdp block again: marker still present (idempotent)"
n=$(rich | grep -cE 'port="3389"')
assert_eq "$n" "1" "rdp: exactly one rule (no duplicate after second block)"
sudo -n "$HELP" allow rdp >/dev/null
assert_eq "$(marker 'port="3389"')" "no" "rdp allow: marker gone again"

# --- vnc: block -> marker present, allow -> marker gone ---------------------
sudo -n "$HELP" block vnc >/dev/null
assert_eq "$(marker 'port="5900-5903"')" "yes" "vnc block: marker present"
sudo -n "$HELP" allow vnc >/dev/null
assert_eq "$(marker 'port="5900-5903"')" "no" "vnc allow: marker gone again"

# --- sunshine: block -> both markers (tcp+udp) present, allow -> both gone --
sudo -n "$HELP" block sunshine >/dev/null
assert_eq "$(marker 'port="47984-48010"')" "yes" "sunshine block: tcp range marker present"
assert_eq "$(marker 'port="47998-48000"')" "yes" "sunshine block: udp range marker present"
sudo -n "$HELP" allow sunshine >/dev/null
assert_eq "$(marker 'port="47984-48010"')" "no" "sunshine allow: tcp marker gone again"
assert_eq "$(marker 'port="47998-48000"')" "no" "sunshine allow: udp marker gone again"

# --- comfyui: block -> marker present, allow -> marker gone -----------------
sudo -n "$HELP" block comfyui >/dev/null
assert_eq "$(marker 'port="8188"')" "yes" "comfyui block: marker present"
sudo -n "$HELP" allow comfyui >/dev/null
assert_eq "$(marker 'port="8188"')" "no" "comfyui allow: marker gone again"

# --- Cleanup: ensure all four apps end up 'allow' ---------------------------
for app in rdp vnc sunshine comfyui; do
    sudo -n "$HELP" allow "$app" >/dev/null 2>&1 || true
done
after=$(rich)
assert_eq "$after" "$before" "final state: rich-rules match pre-test state (no leftover reject)"

pass
