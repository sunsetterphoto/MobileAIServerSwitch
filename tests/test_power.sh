#!/usr/bin/env bash
# Live test of the power/radio switches (dGPU/WiFi/BT/EPP/ASPM/WoL). Authorized:
# no Bluetooth device in use, WiFi carries nothing critical, the default route
# + Tailscale run over Ethernet. Self-restoring: ends in the safe default state
# (wifi on, bt on, gpu auto, epp balance_performance, aspm default, wol on/g).
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
CLI=bin/msw-power
. bin/msw-config
NIC=$(detect_wol_nic)
[ -z "$NIC" ] && NIC=$(detect_lan_ifaces | awk '{print $1}')

assert "[ -x $CLI ]" "msw-power is executable"

gpu_ctrl() { cat /sys/bus/pci/devices/0000:01:00.0/power/control; }
wifi_blocked() { rfkill list wifi | awk -F': ' '/Soft blocked/{print $2; exit}'; }
bt_blocked_any() { rfkill list bluetooth | grep -q 'Soft blocked: yes' && echo yes || echo no; }
epp0() { cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference; }
aspm_policy() { grep -oP '\[\K[^]]+' /sys/module/pcie_aspm/parameters/policy; }
wake_on() { sudo -n ethtool "$NIC" | awk -F': ' '/^[[:space:]]*Wake-on:/{print $2; exit}'; }

# --- gpu ---
$CLI gpu keep >/dev/null
assert_eq "$(gpu_ctrl)" "on" "gpu keep -> power/control=on"
$CLI gpu auto >/dev/null
assert_eq "$(gpu_ctrl)" "auto" "gpu auto -> power/control=auto"

# --- wifi (authorized: nothing critical on WiFi) ---
$CLI wifi off >/dev/null
assert_eq "$(wifi_blocked)" "yes" "wifi off -> soft blocked"
$CLI wifi on >/dev/null
assert_eq "$(wifi_blocked)" "no" "wifi on -> not soft blocked"

# --- bt (authorized: no BT device in use) ---
$CLI bt off >/dev/null
assert_eq "$(bt_blocked_any)" "yes" "bt off -> soft blocked"
$CLI bt on >/dev/null
assert_eq "$(bt_blocked_any)" "no" "bt on -> not soft blocked"

# --- epp ---
$CLI epp power >/dev/null
assert_eq "$(epp0)" "power" "epp power set"
# invalid value is rejected, changes nothing
$CLI epp bogus 2>/dev/null && { echo "FAIL: epp bogus should have been rejected"; exit 1; }
assert_eq "$(epp0)" "power" "epp bogus did not change epp"
$CLI epp balance_performance >/dev/null
assert_eq "$(epp0)" "balance_performance" "epp restore balance_performance"

# --- aspm ---
# On this class of device the ACPI FADT reports "PCIe ASPM unsupported"
# (verified via `journalctl -k`: "FADT indicates ASPM is unsupported, using
# BIOS configuration"), so the kernel rejects policy writes with EPERM -- even
# as root, this is not a limitation of msw-power-apply. The helper detects
# this via the readback check and correctly fails (non-zero, unchanged)
# instead of silently reporting "success". We therefore test exactly this
# fail-safe path.
assert_eq "$(aspm_policy)" "default" "aspm initial state = default"
$CLI aspm powersave 2>/dev/null && { echo "FAIL: aspm powersave should fail on this system due to the ACPI FADT lockout (EPERM)"; exit 1; }
assert_eq "$(aspm_policy)" "default" "aspm powersave (EPERM) did not change the policy"
# invalid value is rejected before any write attempt, changes nothing
$CLI aspm bogus 2>/dev/null && { echo "FAIL: aspm bogus should have been rejected"; exit 1; }
assert_eq "$(aspm_policy)" "default" "aspm bogus did not change the policy"

# --- wol (authorized: default route + Tailscale run over Ethernet, WoL stays on) ---
$CLI wol off >/dev/null
assert_eq "$(wake_on)" "d" "wol off -> Wake-on=d"
$CLI wol on >/dev/null
assert_eq "$(wake_on)" "g" "wol on -> Wake-on=g"

pass
