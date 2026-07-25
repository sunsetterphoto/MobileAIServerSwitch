#!/usr/bin/env bash
# Performance axis: band definition, all three presets end-to-end, the fine cap,
# and argument validation. Self-restoring: ends on balanced.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
PSTATE=/sys/devices/system/cpu/intel_pstate
max_pct()  { cat "$PSTATE/max_perf_pct"; }
no_turbo() { cat "$PSTATE/no_turbo"; }
active_profile() {
  busctl --system get-property org.freedesktop.UPower.PowerProfiles \
    /org/freedesktop/UPower/PowerProfiles \
    org.freedesktop.UPower.PowerProfiles ActiveProfile 2>/dev/null | sed 's/^s "//;s/"$//'
}

assert "[ -x bin/msw-perf ]" "msw-perf is executable"

# The band definition is the single source of truth
read -r lo hi tgt turbo <<<"$(bin/msw-perf band balanced)"
assert_eq "$tgt" "70" "balanced target = 70"
assert_eq "$turbo" "on" "balanced turbo on"
read -r lo hi tgt turbo <<<"$(bin/msw-perf band power-saver)"
assert_eq "$tgt" "40" "power-saver target = 40"
assert_eq "$turbo" "off" "power-saver turbo off"

# --- all three presets end-to-end: profile AND cap AND turbo must match the band.
# (Verified beforehand that tuned-ppd does not asynchronously overwrite the cap
# in any of the three profiles.)
bin/msw-perf performance >/dev/null
assert_eq "$(max_pct)" "100" "performance -> 100%"
assert_eq "$(no_turbo)" "0" "performance -> turbo on"
assert_eq "$(active_profile)" "performance" "D-Bus profile = performance"

bin/msw-perf power-saver >/dev/null
assert_eq "$(max_pct)" "40" "power-saver -> 40%"
assert_eq "$(no_turbo)" "1" "power-saver -> turbo off"
assert_eq "$(active_profile)" "power-saver" "D-Bus profile = power-saver"

bin/msw-perf balanced >/dev/null
assert_eq "$(max_pct)" "70" "balanced -> 70%"
assert_eq "$(no_turbo)" "0" "balanced -> turbo on"
assert_eq "$(active_profile)" "balanced" "D-Bus profile = balanced"

# pct-only doesn't change the profile
bin/msw-perf pct 55 >/dev/null
assert_eq "$(max_pct)" "55" "pct 55 set"
assert_eq "$(active_profile)" "balanced" "pct kept the profile at balanced"

# --- argument validation: a rejected call must change nothing ------------------
bin/msw-perf balanced 55 2>/dev/null && { echo "FAIL: surplus argument after a preset should be rejected"; exit 1; }
assert_eq "$(max_pct)" "55" "rejected 'balanced 55' changed no cap"
bin/msw-perf pct 2>/dev/null && { echo "FAIL: pct without a value should be rejected"; exit 1; }
bin/msw-perf pct 55 99 2>/dev/null && { echo "FAIL: pct with a surplus argument should be rejected"; exit 1; }
bin/msw-perf band 2>/dev/null && { echo "FAIL: band without a profile should be rejected"; exit 1; }
bin/msw-perf band balanced extra 2>/dev/null && { echo "FAIL: band with a surplus argument should be rejected"; exit 1; }
assert_eq "$(max_pct)" "55" "no rejected call touched the cap"

# clean state
bin/msw-perf balanced >/dev/null
assert_eq "$(max_pct)" "70" "restored to balanced/70%"
pass
