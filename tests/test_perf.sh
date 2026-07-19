#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
assert "[ -x bin/msw-perf ]" "msw-perf is executable"
# The band definition is the single source of truth
read -r lo hi tgt turbo <<<"$(bin/msw-perf band balanced)"
assert_eq "$tgt" "70" "balanced target = 70"
assert_eq "$turbo" "on" "balanced turbo on"
read -r lo hi tgt turbo <<<"$(bin/msw-perf band power-saver)"
assert_eq "$tgt" "40" "power-saver target = 40"
assert_eq "$turbo" "off" "power-saver turbo off"
# apply preset: performance -> 100% / turbo on / profile performance
bin/msw-perf performance >/dev/null
assert_eq "$(cat /sys/devices/system/cpu/intel_pstate/max_perf_pct)" "100" "performance -> 100%"
prof=$(busctl --system get-property org.freedesktop.UPower.PowerProfiles \
  /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile 2>/dev/null | sed 's/^s "//;s/"$//')
assert_eq "$prof" "performance" "D-Bus profile = performance"
# pct-only doesn't change the profile
bin/msw-perf pct 55 >/dev/null
assert_eq "$(cat /sys/devices/system/cpu/intel_pstate/max_perf_pct)" "55" "pct 55 set"
# clean state
bin/msw-perf balanced >/dev/null
pass
