#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
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
assert "jq -e '.gpu.present' >/dev/null <<<\"\$J\""       "has .gpu.present"
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
assert "jq -e '.firewall.apps.rdp.blocked | type == \"boolean\"' >/dev/null <<<\"\$J\""      "firewall.apps.rdp.blocked is bool"
assert "jq -e '.firewall.apps.vnc.blocked | type == \"boolean\"' >/dev/null <<<\"\$J\""      "firewall.apps.vnc.blocked is bool"
assert "jq -e '.firewall.apps.sunshine.blocked | type == \"boolean\"' >/dev/null <<<\"\$J\"" "firewall.apps.sunshine.blocked is bool"
assert "jq -e '.firewall.apps.comfyui.blocked | type == \"boolean\"' >/dev/null <<<\"\$J\""  "firewall.apps.comfyui.blocked is bool"
assert "jq -e '.firewall.high_ports_open | type == \"boolean\"' >/dev/null <<<\"\$J\""       "firewall.high_ports_open is bool"
assert "jq -e '.firewall.ssh_allowed == true' >/dev/null <<<\"\$J\""                          "firewall.ssh_allowed == true"
pass
