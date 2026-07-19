#!/usr/bin/env bash
# Test of the config loader + auto-detection library (bin/msw-config). Pure
# read-only checks against the running host -- no firewall/power state is
# ever changed.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh

# --- sourceable ----------------------------------------------------------------
assert "[ -r bin/msw-config ]" "bin/msw-config exists and is readable"
# A guaranteed-absent config path makes the "missing file" case deterministic,
# independent of whatever happens to be on this host under ~/.config.
export MSW_CONFIG_FILE=/nonexistent/mobileserverswitch/config.json
. bin/msw-config
assert "declare -F msw_cfg >/dev/null"          "msw_cfg is defined after sourcing"
assert "declare -F cfg_or_detect >/dev/null"    "cfg_or_detect is defined after sourcing"
assert "declare -F detect_lan_ifaces >/dev/null" "detect_lan_ifaces is defined after sourcing"
assert "declare -F detect_tailnet_ip4 >/dev/null" "detect_tailnet_ip4 is defined after sourcing"
assert "declare -F has_tailscale >/dev/null"    "has_tailscale is defined after sourcing"
assert "declare -F detect_firewall_zone >/dev/null" "detect_firewall_zone is defined after sourcing"
assert "declare -F detect_wol_nic >/dev/null"   "detect_wol_nic is defined after sourcing"

# --- msw_cfg: missing file -> default -------------------------------------------
assert_eq "$(msw_cfg network.firewall_zone myDefault)" "myDefault" "msw_cfg returns default when config file absent"
assert_eq "$(msw_cfg any.key fallback)" "fallback" "msw_cfg returns default for any key when config file absent"

# --- msw_cfg: present file, key found / missing / null --------------------------
TMP_CFG=$(mktemp)
trap 'rm -f "$TMP_CFG"' EXIT
cat > "$TMP_CFG" <<'JSON'
{ "network": { "lan_interfaces": "eth9", "firewall_zone": null } }
JSON
MSW_CONFIG_FILE="$TMP_CFG"
assert_eq "$(msw_cfg network.lan_interfaces auto)" "eth9" "msw_cfg reads a present key"
assert_eq "$(msw_cfg network.firewall_zone auto)"  "auto" "msw_cfg falls back to default for a null key"
assert_eq "$(msw_cfg network.does_not_exist auto)" "auto" "msw_cfg falls back to default for a missing key"
export MSW_CONFIG_FILE=/nonexistent/mobileserverswitch/config.json

# --- cfg_or_detect: "auto"/empty config -> detection wins -----------------------
fake_detect() { echo "fake-value"; }
assert_eq "$(cfg_or_detect network.does_not_exist fake_detect)" "fake-value" "cfg_or_detect falls through to detection when unset"
MSW_CONFIG_FILE="$TMP_CFG"
assert_eq "$(cfg_or_detect network.lan_interfaces fake_detect)" "eth9" "cfg_or_detect prefers a real config value over detection"
export MSW_CONFIG_FILE=/nonexistent/mobileserverswitch/config.json

# --- detect_lan_ifaces -----------------------------------------------------------
lan=$(detect_lan_ifaces)
assert "[ -n \"\$lan\" ]" "detect_lan_ifaces is non-empty on this host (has a default route)"

# --- detect_firewall_zone -------------------------------------------------------
if command -v firewall-cmd >/dev/null 2>&1; then
    assert_eq "$(detect_firewall_zone)" "$(firewall-cmd --get-default-zone 2>/dev/null)" "detect_firewall_zone matches firewall-cmd --get-default-zone"
else
    assert_eq "$(detect_firewall_zone)" "" "detect_firewall_zone is empty when firewall-cmd is absent"
fi

# --- has_tailscale ---------------------------------------------------------------
if command -v tailscale >/dev/null 2>&1 && [ -e /sys/class/net/tailscale0 ]; then
    assert "has_tailscale" "has_tailscale is true (tailscale binary + tailscale0 present)"
else
    assert "! has_tailscale" "has_tailscale is false (tailscale binary or tailscale0 missing)"
fi

# --- detect_tailnet_ip4 -----------------------------------------------------------
assert_eq "$(detect_tailnet_ip4)" "$(tailscale ip -4 2>/dev/null | head -1)" "detect_tailnet_ip4 matches tailscale ip -4 | head -1"

# --- detect_wol_nic: must be one of detect_lan_ifaces, and wired -----------------
wol=$(detect_wol_nic)
if [ -n "$wol" ]; then
    assert "[[ \" \$lan \" == *\" \$wol \"* ]]" "detect_wol_nic ($wol) is one of the detected LAN interfaces"
    assert "[ ! -e /sys/class/net/$wol/wireless ]" "detect_wol_nic ($wol) is wired (no wireless sysfs node)"
fi

pass
