#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
HELP=system/usr-local-sbin/msw-perf-apply
assert "[ -x $HELP ]" "msw-perf-apply is executable"
# invalid value is rejected
before=$(cat /sys/devices/system/cpu/intel_pstate/max_perf_pct)
sudo -n "$PWD/$HELP" 5 on 2>/dev/null && { echo "FAIL: 5% should have been rejected"; exit 1; }
assert_eq "$(cat /sys/devices/system/cpu/intel_pstate/max_perf_pct)" "$before" "reject 5 must not change max_perf_pct"
# overlong argument is rejected
sudo -n "$PWD/$HELP" 99999 on 2>/dev/null && { echo "FAIL: 99999 should have been rejected"; exit 1; }
# valid: 60% turbo off
sudo -n "$PWD/$HELP" 60 off >/dev/null
assert_eq "$(cat /sys/devices/system/cpu/intel_pstate/max_perf_pct)" "60" "max_perf_pct=60 set"
assert_eq "$(cat /sys/devices/system/cpu/intel_pstate/no_turbo)" "1" "no_turbo=1 (turbo off)"
# min belongs to tuned (can rise asynchronously) -> only check the invariant
# that makes the cap honorable: min <= cap.
assert "[ \"$(cat /sys/devices/system/cpu/intel_pstate/min_perf_pct)\" -le 60 ]" "min_perf_pct <= cap (cap takes effect)"
# back to 100/turbo on (clean state)
sudo -n "$PWD/$HELP" 100 on >/dev/null
assert_eq "$(cat /sys/devices/system/cpu/intel_pstate/no_turbo)" "0" "no_turbo=0 (turbo on)"
pass
