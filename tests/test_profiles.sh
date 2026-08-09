#!/usr/bin/env bash
# Tests of the profile system: bin/msw-mode (list / apply / keep semantics /
# legacy fallback) and system/usr-local-sbin/msw-charge-apply (threshold
# resolution against the profiles schema + legacy schema).
#
# Nothing on the host is touched: every external command msw-mode delegates to
# (kwriteconfig6, kreadconfig6, busctl, systemctl, sudo, kscreen-doctor,
# msw-perf, msw-power) is intercepted by a PATH stub that only logs its
# arguments to $STUB_LOG. Config and state files point into a temp dir via
# the MSW_CONFIG_FILE / MSW_STATE_FILE overrides.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

CFG_FILE="$WORKDIR/config.json"
STATE_FILE="$WORKDIR/state"
export MSW_CONFIG_FILE="$CFG_FILE"
export MSW_STATE_FILE="$STATE_FILE"

STUB_BIN="$WORKDIR/bin"
STUB_LOG="$WORKDIR/stub.log"
mkdir -p "$STUB_BIN"
: > "$STUB_LOG"

# make_stub <name> — stub that logs "<name> <args...>" per call and exits 0
make_stub() {
    cat > "$STUB_BIN/$1" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' "$1" "\$*" >> "$STUB_LOG"
exit 0
EOF
    chmod +x "$STUB_BIN/$1"
}
for cmd in kwriteconfig6 kreadconfig6 busctl systemctl sudo kscreen-doctor msw-perf msw-power; do
    make_stub "$cmd"
done
export PATH="$STUB_BIN:$PATH"

reset_log() { : > "$STUB_LOG"; }

CHARGE_APPLY=system/usr-local-sbin/msw-charge-apply
# True if this host has charge-threshold sysfs support (decides which branch
# of the positive-pair assertions applies: a real write attempt as non-root
# must fail honestly; without hardware the helper skips before any write).
have_threshold_hw=false
for _d in /sys/class/power_supply/*/; do
    [ -e "${_d}charge_control_end_threshold" ] && have_threshold_hw=true && break
done
unset _d

# --- msw-mode list: no config file -> the two builtin profiles with defaults ----
rm -f "$CFG_FILE" "$STATE_FILE"
out=$(bin/msw-mode list)
assert_eq "$?" "0" "msw-mode list exits 0"
assert_eq "$(wc -l <<<"$out")" "2" "list without config: exactly the 2 builtin profiles"
assert_eq "$(sed -n '1p' <<<"$out")" $'server\tServer\tnetwork-server\t-' "list: builtin server row (id/label/icon/active)"
assert_eq "$(sed -n '2p' <<<"$out")" $'laptop\tLaptop\tcomputer-laptop\t-' "list: builtin laptop row (id/label/icon/active)"

# active marker comes from the state file
echo laptop > "$STATE_FILE"
out=$(bin/msw-mode list)
assert_eq "$(sed -n '2p' <<<"$out")" $'laptop\tLaptop\tcomputer-laptop\tactive' "list: state-file profile is marked active"
assert_eq "$(sed -n '1p' <<<"$out")" $'server\tServer\tnetwork-server\t-' "list: other profile keeps '-' marker"
rm -f "$STATE_FILE"

# --- msw-mode list: custom profile from config ------------------------------------
cat > "$CFG_FILE" <<'JSON'
{ "profiles": { "gaming": { "label": "Gaming", "icon": "input-gaming" } } }
JSON
out=$(bin/msw-mode list)
assert_eq "$(wc -l <<<"$out")" "3" "list with custom profile: 2 builtins + 1 custom"
assert_eq "$(sed -n '3p' <<<"$out")" $'gaming\tGaming\tinput-gaming\t-' "list: custom row shows configured label/icon (builtins first, customs after)"
assert_eq "$(sed -n '1p' <<<"$out")" $'server\tServer\tnetwork-server\t-' "list: builtins still come first"

# --- apply custom profile with template defaults -> touches nothing --------------
reset_log
bin/msw-mode gaming >/dev/null 2>&1
assert_eq "$?" "0" "msw-mode <custom> with template defaults exits 0"
assert "! grep -q '^kwriteconfig6 ' \"$STUB_LOG\"" "all-keep template profile: no kwriteconfig6 call"
assert "! grep -q '^msw-power ' \"$STUB_LOG\"" "all-keep template profile: no msw-power call"
assert "! grep -q '^msw-perf ' \"$STUB_LOG\"" "all-keep template profile: no msw-perf call"
assert "! grep -q '^busctl ' \"$STUB_LOG\"" "all-keep template profile: no busctl call (no refreshStatus/reconfigure)"
assert "! grep -q '^kscreen-doctor ' \"$STUB_LOG\"" "all-keep template profile: no kscreen-doctor call (display all null)"
assert "! grep -q '^systemctl ' \"$STUB_LOG\"" "all-keep template profile: no systemctl call (empty service lists)"
assert "grep -q 'msw-charge-apply' \"$STUB_LOG\"" "profile id persist + msw-charge-apply still attempted via sudo"

# --- apply builtin laptop profile (no config file -> builtin defaults) -----------
rm -f "$CFG_FILE"
reset_log
bin/msw-mode laptop >/dev/null 2>&1
assert_eq "$?" "0" "msw-mode laptop exits 0"
assert "grep -q -- '--key LidAction 1' \"$STUB_LOG\"" "laptop: LidAction=1 (sleep) written"
assert "grep -q -- '--key PowerButtonAction 16' \"$STUB_LOG\"" "laptop: PowerButtonAction=16 (prompt) written"
assert "grep -q -- '--key PowerDownAction 8' \"$STUB_LOG\"" "laptop: PowerDownAction=8 (shutdown) written"
assert "grep -q -- '--key AutoSuspendAction 1' \"$STUB_LOG\"" "laptop: AutoSuspendAction=1 (sleep) written"
assert "grep -q -- '--key AutoSuspendIdleTimeoutSec 1800' \"$STUB_LOG\"" "laptop: AutoSuspendIdleTimeoutSec=1800 (30 min x 60)"
assert "grep -q -- '--key TurnOffDisplayWhenIdle --type bool true' \"$STUB_LOG\"" "laptop: TurnOffDisplayWhenIdle=true written"
assert "grep -q -- '--key TurnOffDisplayIdleTimeoutSec 600' \"$STUB_LOG\"" "laptop: TurnOffDisplayIdleTimeoutSec=600 (10 min x 60)"
assert "grep -q -- '--key DimDisplayWhenIdle --type bool true' \"$STUB_LOG\"" "laptop: DimDisplayWhenIdle=true written"
assert "grep -q -- '--key DimDisplayIdleTimeoutSec 300' \"$STUB_LOG\"" "laptop: DimDisplayIdleTimeoutSec=300 (5 min x 60)"
assert_eq "$(grep -c -- '--key LidAction 1' "$STUB_LOG")" "3" "laptop: LidAction written for all 3 PowerDevil profiles (AC/Battery/LowBattery)"
assert "grep -q -- '--file kscreenlockerrc .*--key Autolock --type bool true' \"$STUB_LOG\"" "laptop: locker Autolock=true written"
assert "grep -q -- '--file kscreenlockerrc .*--key Timeout 5' \"$STUB_LOG\"" "laptop: locker Timeout=5 written"
assert "grep -q '^msw-perf balanced' \"$STUB_LOG\"" "laptop: performance.profile -> msw-perf balanced"
assert "grep -q '^msw-power wifi on' \"$STUB_LOG\"" "laptop: radios.wifi=on -> msw-power wifi on"
assert "grep -q '^msw-power wol off' \"$STUB_LOG\"" "laptop: power.wol=off -> msw-power wol off"
assert "! grep -q '^msw-power bt ' \"$STUB_LOG\"" "laptop: radios.bluetooth=keep -> no msw-power bt call"
assert "grep -q '^systemctl --user stop sunshine' \"$STUB_LOG\"" "laptop: services.stop -> systemctl stop (sunshine, unresolved id as-is)"
assert "grep -q 'msw-charge-apply' \"$STUB_LOG\"" "laptop: sudo msw-charge-apply attempted"
assert "grep -q 'refreshStatus' \"$STUB_LOG\"" "laptop: PowerDevil refreshStatus called (keys were written)"

# --- builtin server: screen_off_min/dim_min 0 = actively "never" (not keep) ---
rm -f "$CFG_FILE"
reset_log
bin/msw-mode server >/dev/null 2>&1
assert_eq "$?" "0" "msw-mode server exits 0"
assert_eq "$(grep -c -- '--key TurnOffDisplayWhenIdle --type bool false' "$STUB_LOG")" "3" "server: screen_off_min=0 writes TurnOffDisplayWhenIdle=false for all 3 PowerDevil profiles"
assert_eq "$(grep -c -- '--key DimDisplayWhenIdle --type bool false' "$STUB_LOG")" "3" "server: dim_min=0 writes DimDisplayWhenIdle=false for all 3 PowerDevil profiles"
assert "! grep -q -- '--key TurnOffDisplayIdleTimeoutSec' \"$STUB_LOG\"" "server: no display-off timeout written (0 = never, not N minutes)"

# --- custom profile: screen_off_min/dim_min null = keep -------------------------
cat > "$CFG_FILE" <<'JSON'
{ "profiles": { "scrkeep": { "power": { "screen_off_min": null, "dim_min": null } } } }
JSON
reset_log
bin/msw-mode scrkeep >/dev/null 2>&1
assert_eq "$?" "0" "msw-mode scrkeep exits 0"
assert "! grep -q 'TurnOffDisplay\|DimDisplay' \"$STUB_LOG\"" "screen_off_min/dim_min null: display-off/dim keys untouched"
assert "! grep -q '^kwriteconfig6 ' \"$STUB_LOG\"" "screen_off_min/dim_min null: no kwriteconfig6 at all (all else keep)"

# --- keep semantics: profile with only power.lid_action set -----------------------
cat > "$CFG_FILE" <<'JSON'
{ "profiles": { "minimal": { "label": "Minimal", "power": { "lid_action": "sleep" } } } }
JSON
reset_log
bin/msw-mode minimal >/dev/null 2>&1
assert_eq "$?" "0" "msw-mode minimal exits 0"
assert_eq "$(grep -c '^kwriteconfig6 ' "$STUB_LOG")" "3" "keep semantics: exactly 3 kwriteconfig6 calls (LidAction x AC/Battery/LowBattery)"
assert_eq "$(grep -c -- '--key LidAction 1' "$STUB_LOG")" "3" "keep semantics: all 3 writes are LidAction=1 (sleep)"
assert "! grep -q 'TurnOffDisplay' \"$STUB_LOG\"" "keep semantics: no TurnOffDisplay key written"
assert "! grep -q 'AutoSuspend' \"$STUB_LOG\"" "keep semantics: no AutoSuspend key written"
assert "! grep -q 'kscreenlockerrc' \"$STUB_LOG\"" "keep semantics: locker untouched (autolock=keep)"
assert "! grep -q '^msw-power ' \"$STUB_LOG\"" "keep semantics: no msw-power call (radios/wol/dgpu all keep/null)"
assert "! grep -q '^msw-perf ' \"$STUB_LOG\"" "keep semantics: no msw-perf call (performance all null)"

# --- unknown profile id -> exit 2 ---------------------------------------------------
err=$(bin/msw-mode nosuchprofile 2>&1 >/dev/null)
code=$?
assert_eq "$code" "2" "unknown profile id exits 2"
assert "grep -q 'unknown profile' <<<\"\$err\"" "unknown profile id: error message on stderr"
assert "grep -q 'msw-mode list' <<<\"\$err\"" "unknown profile id: message points at 'msw-mode list'"

# --- legacy fallback: config WITHOUT profiles key -----------------------------------
cat > "$CFG_FILE" <<'JSON'
{ "mode": { "stop_on_laptop": ["x.service"],
            "charge_thresholds": { "enabled": true, "server": "50/90", "laptop": "10/95" } } }
JSON
reset_log
bin/msw-mode laptop >/dev/null 2>&1
assert_eq "$?" "0" "legacy config: msw-mode laptop exits 0"
assert "grep -q '^systemctl --user stop x.service' \"$STUB_LOG\"" "legacy: mode.stop_on_laptop -> laptop stops x.service"
assert "! grep -q 'stop sunshine' \"$STUB_LOG\"" "legacy: stop_on_laptop replaces the builtin stop list (no sunshine)"
assert "grep -q -- '--key LidAction 1' \"$STUB_LOG\"" "legacy: builtin laptop power defaults still apply"

reset_log
bin/msw-mode server >/dev/null 2>&1
assert_eq "$?" "0" "legacy config: msw-mode server exits 0"
assert "grep -q '^systemctl --user start x.service' \"$STUB_LOG\"" "legacy: mode.stop_on_laptop -> server starts x.service"
assert "! grep -q 'start sunshine' \"$STUB_LOG\"" "legacy: stop_on_laptop replaces the builtin start list (no sunshine)"

# --- msw-mode status smoke test (stubbed, exits 0, shows profile id + label) -------
# profiles config: the active profile (laptop, builtin) resolves to its
# builtin defaults, so the services section shows its stop list (sunshine).
cat > "$CFG_FILE" <<'JSON'
{ "profiles": { "gaming": { "label": "Gaming", "icon": "input-gaming" } } }
JSON
echo laptop > "$STATE_FILE"
out=$(bin/msw-mode status 2>/dev/null)
assert_eq "$?" "0" "msw-mode status exits 0"
assert "grep -q 'Saved mode: laptop (Laptop)' <<<\"\$out\"" "status: 'Saved mode' shows profile id + label"
assert "grep -q 'stop:.*sunshine' <<<\"\$out\"" "status: services section shows the active profile's stop list"
rm -f "$STATE_FILE"

# --- msw-charge-apply: profiles schema ------------------------------------------------
# (a) explicit null = per-profile opt-out -> skip, exit 0 (before any sysfs write)
cat > "$CFG_FILE" <<'JSON'
{ "profiles": { "gaming": { "label": "Gaming", "charge_thresholds": null } } }
JSON
echo gaming > "$STATE_FILE"
out=$("$PWD/$CHARGE_APPLY" 2>&1)
assert_eq "$?" "0" "charge-apply: profiles + null thresholds exits 0"
assert "grep -q 'null (opt-out)' <<<\"\$out\"" "charge-apply: null thresholds -> opt-out message"

# (b) custom profile without the key (no builtin default) -> skip, exit 0
cat > "$CFG_FILE" <<'JSON'
{ "profiles": { "gaming": { "label": "Gaming" } } }
JSON
out=$("$PWD/$CHARGE_APPLY" 2>&1)
assert_eq "$?" "0" "charge-apply: custom profile without charge_thresholds exits 0"
assert "grep -q 'no charge_thresholds' <<<\"\$out\"" "charge-apply: missing key on custom profile -> skip message"

# (c) saved profile not defined in the profiles map -> skip, exit 0
echo nosuch > "$STATE_FILE"
out=$("$PWD/$CHARGE_APPLY" 2>&1)
assert_eq "$?" "0" "charge-apply: unknown saved profile exits 0"
assert "grep -q 'not defined' <<<\"\$out\"" "charge-apply: unknown profile -> skip message"

# (d) malformed pair -> skip with warning, exit 0
cat > "$CFG_FILE" <<'JSON'
{ "profiles": { "gaming": { "charge_thresholds": "abc" } } }
JSON
echo gaming > "$STATE_FILE"
out=$("$PWD/$CHARGE_APPLY" 2>&1)
assert_eq "$?" "0" "charge-apply: malformed pair exits 0"
assert "grep -q 'not in NN/NN form' <<<\"\$out\"" "charge-apply: malformed pair -> warning message"

# (e) explicit valid pair on the saved profile -> resolution reaches the write
#     stage: with threshold hardware an unprivileged write must fail honestly
#     (non-zero); without hardware the helper skips with the no-support message.
#     55/77 is deliberately different from any plausible current value.
cat > "$CFG_FILE" <<'JSON'
{ "profiles": { "gaming": { "charge_thresholds": "55/77" } } }
JSON
out=$("$PWD/$CHARGE_APPLY" 2>&1)
code=$?
if $have_threshold_hw; then
    assert "[ \"$code\" -ne 0 ]" "charge-apply: valid pair, hardware present, no root -> write attempt fails honestly (rc=$code)"
else
    assert_eq "$code" "0" "charge-apply: valid pair, no hardware -> exits 0"
    assert "grep -q 'No charge-threshold support' <<<\"\$out\"" "charge-apply: valid pair, no hardware -> no-support message"
fi

# (f) builtin profile (laptop) present but key missing -> builtin default 0/100
cat > "$CFG_FILE" <<'JSON'
{ "profiles": { "laptop": { "label": "Laptop" } } }
JSON
echo laptop > "$STATE_FILE"
out=$("$PWD/$CHARGE_APPLY" 2>&1)
code=$?
if $have_threshold_hw; then
    assert "[ \"$code\" -ne 0 ]" "charge-apply: builtin profile default pair, hardware, no root -> fails honestly (rc=$code)"
else
    assert_eq "$code" "0" "charge-apply: builtin profile default pair, no hardware -> exits 0"
    assert "grep -q 'No charge-threshold support' <<<\"\$out\"" "charge-apply: builtin default pair, no hardware -> no-support message"
fi

# --- msw-charge-apply: legacy schema (no profiles key) --------------------------------
# (g) enabled gate still applies -> skip, exit 0
cat > "$CFG_FILE" <<'JSON'
{ "mode": { "charge_thresholds": { "enabled": false, "laptop": "33/66" } } }
JSON
out=$("$PWD/$CHARGE_APPLY" 2>&1)
assert_eq "$?" "0" "charge-apply legacy: disabled gate exits 0"
assert "grep -q 'disabled' <<<\"\$out\"" "charge-apply legacy: enabled != true -> disabled message"

# (h) enabled + legacy pair -> resolution reaches the write stage (hardware-guarded)
cat > "$CFG_FILE" <<'JSON'
{ "mode": { "charge_thresholds": { "enabled": true, "laptop": "33/66" } } }
JSON
out=$("$PWD/$CHARGE_APPLY" 2>&1)
code=$?
if $have_threshold_hw; then
    assert "[ \"$code\" -ne 0 ]" "charge-apply legacy: enabled pair, hardware, no root -> fails honestly (rc=$code)"
else
    assert_eq "$code" "0" "charge-apply legacy: enabled pair, no hardware -> exits 0"
    assert "grep -q 'No charge-threshold support' <<<\"\$out\"" "charge-apply legacy: enabled pair, no hardware -> no-support message"
fi

# (i) unknown mode in the state file -> legacy fallback to server (message)
echo bogusmode > "$STATE_FILE"
out=$("$PWD/$CHARGE_APPLY" 2>&1)
assert "grep -q \"Unknown mode 'bogusmode'\" <<<\"\$out\"" "charge-apply legacy: unknown mode -> falls back to server with message"

rm -f "$STATE_FILE"

pass
