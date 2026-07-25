#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh

# --- Config backup/restore (real path -- msw-status has no test-only ---------
#     override for it). Any pre-existing config on this host is backed up and
#     restored via the EXIT trap -- this must never leave the host's config
#     altered or a stray temp file behind, whether the test passes or an
#     assert exits early. The base assertions below need a known "no config"
#     starting state (default firewall app whitelist = rdp+vnc only), so the
#     backup/restore setup runs BEFORE the first `msw-status --json` call.
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
rm -f "$CFG_FILE"   # start from "no config" for the base assertions below

J=$(bin/msw-status --json)
# valid JSON?
assert "jq -e . >/dev/null 2>&1 <<<\"\$J\"" "output is valid JSON"
# required fields present
assert "jq -e '.mode' >/dev/null <<<\"\$J\""            "has .mode"
assert "jq -e '.perf.max_perf_pct' >/dev/null <<<\"\$J\"" "has .perf.max_perf_pct"
assert "jq -e '.perf.profile' >/dev/null <<<\"\$J\""     "has .perf.profile"
assert "jq -e '.remote.ssh | has(\"active\")' >/dev/null <<<\"\$J\"" "has .remote.ssh.active"
assert "jq -e '.remote.tailscale.ip4' >/dev/null <<<\"\$J\"" "has .remote.tailscale.ip4"
assert "jq -e '.services | type == \"array\"' >/dev/null <<<\"\$J\"" ".services is an array"
# GPU
# has() instead of truthiness: present=false is a valid answer, not a missing field
assert "jq -e '.gpu | has(\"present\")' >/dev/null <<<\"\$J\""       "has .gpu.present"
assert "jq -e '.gpu.present | type == \"boolean\"' >/dev/null <<<\"\$J\"" ".gpu.present is bool"
assert "jq -e '.gpu | has(\"watts\")' >/dev/null <<<\"\$J\"" "has .gpu.watts (even if null)"
assert "jq -e '.gpu | has(\"awake\")' >/dev/null <<<\"\$J\"" "has .gpu.awake"
assert "jq -e '.gpu | has(\"dstate\")' >/dev/null <<<\"\$J\"" "has .gpu.dstate"
assert "jq -e '.gpu | has(\"control\")' >/dev/null <<<\"\$J\"" "has .gpu.control"
# Power extras
assert "jq -e '.power_extra.epp' >/dev/null <<<\"\$J\""  "has .power_extra.epp"
assert "jq -e '.power_extra.wifi' >/dev/null <<<\"\$J\"" "has .power_extra.wifi"
assert "jq -e '.power_extra | has(\"aspm\")' >/dev/null <<<\"\$J\"" "has .power_extra.aspm"
assert "jq -e '.power_extra | has(\"bt\")' >/dev/null <<<\"\$J\""   "has .power_extra.bt"
# Wake-on-LAN
assert "jq -e '.remote.wol | has(\"enabled\")' >/dev/null <<<\"\$J\"" "has .remote.wol.enabled"
assert "jq -e '.remote.wol | has(\"supported\")' >/dev/null <<<\"\$J\"" "has .remote.wol.supported"
assert "jq -e '.remote.wol | has(\"mode\")' >/dev/null <<<\"\$J\""     "has .remote.wol.mode"
# max_perf_pct within the valid range 16..100
p=$(jq -r '.perf.max_perf_pct' <<<"$J")
assert "[ \"\$p\" -ge 16 ] && [ \"\$p\" -le 100 ]" "max_perf_pct in [16,100] (is $p)"
# Firewall (read-only check -- this test does not change firewall state)
assert "jq -e '.firewall' >/dev/null <<<\"\$J\""                      "has .firewall"
# firewall.apps is config-driven (config.firewall.apps); default (no config,
# as ensured above) is exactly rdp+vnc -- nothing hardcoded to
# sunshine/comfyui here anymore.
assert "jq -e '.firewall.apps.rdp.blocked | type == \"boolean\"' >/dev/null <<<\"\$J\""      "firewall.apps.rdp.blocked is bool"
assert "jq -e '.firewall.apps.vnc.blocked | type == \"boolean\"' >/dev/null <<<\"\$J\""      "firewall.apps.vnc.blocked is bool"
assert "jq -e '.firewall.apps | (has(\"sunshine\") | not)' >/dev/null <<<\"\$J\""            "firewall.apps has no hardcoded sunshine entry by default"
assert "jq -e '.firewall.apps | (has(\"comfyui\") | not)' >/dev/null <<<\"\$J\""             "firewall.apps has no hardcoded comfyui entry by default"
assert "jq -e '.firewall.high_ports_open | type == \"boolean\"' >/dev/null <<<\"\$J\""       "firewall.high_ports_open is bool"
assert "jq -e '.firewall.ssh_allowed == true' >/dev/null <<<\"\$J\""                          "firewall.ssh_allowed == true"

# --- Config-driven services + firewall.apps: temp config with a custom -----
#     service AND a custom firewall app (not rdp/vnc) -- assert both surface
#     correctly and that the default rdp/vnc keys are gone once a config
#     defines its own app list (whitelist is config-sourced, not additive).
mkdir -p "$CFG_DIR"
cat > "$CFG_FILE" <<'JSON'
{
  "services": [ { "id": "testsvc", "label": "Test Service", "unit": "test-svc.service", "scope": "user", "port": 9999 } ],
  "firewall": { "apps": [ { "id": "myapp", "ports_tcp": "9999" } ] }
}
JSON

J2=$(bin/msw-status --json)
assert "jq -e '.services | length == 1' >/dev/null <<<\"\$J2\""            "config-driven services: exactly one entry from temp config"
assert "jq -e '.services[0].id == \"testsvc\"' >/dev/null <<<\"\$J2\""     "config-driven services: id matches the config entry"
assert "jq -e '.services[0].unit == \"test-svc.service\"' >/dev/null <<<\"\$J2\"" "config-driven services: unit is carried through"
assert "jq -e '.services[0] | has(\"active\")' >/dev/null <<<\"\$J2\""    "config-driven services: has active"
assert "jq -e '.services[0] | has(\"exposure\")' >/dev/null <<<\"\$J2\""  "config-driven services: has exposure"
assert "jq -e '.firewall.apps | has(\"myapp\")' >/dev/null <<<\"\$J2\""              "config-driven firewall.apps: custom app id present"
assert "jq -e '.firewall.apps.myapp.blocked | type == \"boolean\"' >/dev/null <<<\"\$J2\"" "config-driven firewall.apps: myapp.blocked is bool"
assert "jq -e '.firewall.apps | (has(\"rdp\") | not)' >/dev/null <<<\"\$J2\""        "config-driven firewall.apps: default rdp key gone once config defines its own apps"

# --- exposure_for_port: unit test against a stubbed `ss` ----------------------
# The classification decides whether the widget claims a port is reachable from
# the LAN, so it is tested against fabricated socket lists instead of whatever
# happens to listen on this host. The function and its two prefix constants are
# extracted from the shipped CLI, so this exercises the real code, not a copy.
(
    eval "$(sed -n '/^TAILNET_PREFIX=/p;/^TAILNET_PREFIX6=/p;/^exposure_for_port()/,/^}/p' bin/msw-status)"
    STUB=""
    ss() { printf '%s' "$STUB"; }     # exposure_for_port only reads column 4
    exposure_of() { STUB=$(printf 'LISTEN 0 128 %s *:*\n' $1); exposure_for_port 3389; }

    assert_eq "$(exposure_of '100.75.62.108:3389')"      "Tailnet"   "IPv4 CGNAT address = Tailnet"
    # Regression: a Tailscale IPv6 (ULA fd7a:115c:a1e0::/48) used to fall through
    # to the default branch and was reported as LAN -- i.e. "reachable from the
    # LAN" for a socket that is bound to the tailnet only.
    assert_eq "$(exposure_of '[fd7a:115c:a1e0::1]:3389')" "Tailnet"   "Tailscale IPv6 ULA = Tailnet, not LAN"
    assert_eq "$(exposure_of '[FD7A:115C:A1E0::1]:3389')" "Tailnet"   "Tailscale IPv6 matched case-insensitively"
    assert_eq "$(exposure_of '127.0.0.1:3389')"          "localhost" "loopback IPv4 = localhost"
    assert_eq "$(exposure_of '[::1]:3389')"              "localhost" "loopback IPv6 = localhost"
    assert_eq "$(exposure_of '192.168.1.5:3389')"        "LAN"       "private IPv4 = LAN"
    assert_eq "$(exposure_of '[fe80::1%enp11s0]:3389')"  "LAN"       "link-local with zone index = LAN"
    assert_eq "$(exposure_of '[::]:3389')"               "LAN"       "wildcard bind = LAN"
    assert_eq "$(exposure_of '[fd7a:115c:a1e0::1]:3389 192.168.1.5:3389')" "LAN" \
              "a LAN socket outweighs the tailnet one"
    assert_eq "$(exposure_of '127.0.0.1:3389 [fd7a:115c:a1e0::1]:3389')" "localhost+Tailnet" \
              "loopback + tailnet listed together"
    STUB=""
    assert_eq "$(exposure_for_port 3389)"                ""          "nothing listening = empty"
) || exit 1

pass
