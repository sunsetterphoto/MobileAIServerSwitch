#!/usr/bin/env bash
# Input validation of the privileged power helper.
#
# Deliberately runs WITHOUT sudo: every branch validates its value BEFORE it
# touches rfkill/sysfs/ethtool, so a rejected call must fail identically with
# or without privileges -- and this test can prove that without switching any
# hardware. The switching itself is covered end-to-end by test_power.sh.
#
# Contract under test: exit 2 = bad invocation (unknown switch, missing/surplus
# argument, invalid value), exit 1 = tried and failed. Never a silent success.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
HELP=system/usr-local-sbin/msw-power-apply

assert "[ -x $HELP ]" "msw-power-apply is executable"

run() { "$PWD/$HELP" "$@" >/dev/null 2>&1; echo $?; }

# state that a rejected call must not touch
gpu_ctrl()   { cat /sys/bus/pci/devices/0000:01:00.0/power/control 2>/dev/null || echo "n/a"; }
wifi_block() { rfkill list wifi | awk -F': ' '/Soft blocked/{print $2; exit}'; }
bt_block()   { rfkill list bluetooth | awk -F': ' '/Soft blocked/{print $2; exit}'; }
epp0()       { cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference; }
BEFORE="$(gpu_ctrl)|$(wifi_block)|$(bt_block)|$(epp0)"

# --- wrong invocation ---------------------------------------------------------
assert_eq "$(run)"               "2" "no argument -> exit 2"
assert_eq "$(run gpu)"           "2" "missing value -> exit 2"
assert_eq "$(run gpu keep extra)" "2" "surplus argument -> exit 2"
assert_eq "$(run bogus on)"      "2" "unknown switch -> exit 2"
assert_eq "$(run '' '')"         "2" "empty switch -> exit 2"

# --- invalid value, one per branch (all six switches) -------------------------
assert_eq "$(run gpu bogus)"   "2" "gpu: invalid value -> exit 2"
assert_eq "$(run wifi bogus)"  "2" "wifi: invalid value -> exit 2"
assert_eq "$(run bt bogus)"    "2" "bt: invalid value -> exit 2"
assert_eq "$(run epp bogus)"   "2" "epp: value not in available preferences -> exit 2"
assert_eq "$(run aspm bogus)"  "2" "aspm: invalid policy -> exit 2"
assert_eq "$(run wol bogus)"   "2" "wol: invalid value -> exit 2"

# case matters: values are matched exactly, no accidental uppercase acceptance
assert_eq "$(run wifi ON)"     "2" "wifi: 'ON' is not 'on' -> exit 2"
assert_eq "$(run gpu KEEP)"    "2" "gpu: 'KEEP' is not 'keep' -> exit 2"

# --- nothing may have changed --------------------------------------------------
assert_eq "$(gpu_ctrl)|$(wifi_block)|$(bt_block)|$(epp0)" "$BEFORE" \
          "no rejected call changed gpu/wifi/bt/epp"

# --- valid value without privileges: must fail honestly, not silently succeed --
# (sysfs belongs to root, so the writability check has to bite.)
rc=$(run gpu keep)
assert "[ \"$rc\" != 0 ]" "valid value without root does not report success (rc=$rc)"
assert_eq "$(gpu_ctrl)" "${BEFORE%%|*}" "failed gpu call left power/control alone"

pass
