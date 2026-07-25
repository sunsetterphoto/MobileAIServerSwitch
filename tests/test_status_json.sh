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

# --- Regression: invalid firewall_zone must not read as "firewalld down" ---
#     network.firewall_zone is user-editable config. msw-status asks
#     firewall-cmd --list-all for that zone in one call; if the zone name is
#     wrong, that call fails with INVALID_ZONE even though firewalld itself
#     is running fine. That must stay distinguishable from firewalld being
#     absent/dead: zone stays the configured (bogus) name, not null. Only
#     meaningful when firewalld is actually running on the test host.
if firewall-cmd --state >/dev/null 2>&1; then
    cat > "$CFG_FILE" <<'JSON'
{ "network": { "firewall_zone": "no-such-zone-xyz" } }
JSON
    J3=$(bin/msw-status --json)
    assert "jq -e '.firewall.zone != null' >/dev/null <<<\"\$J3\""            "invalid firewall_zone + firewalld running: .firewall.zone is not null"
    assert "jq -e '.firewall.zone == \"no-such-zone-xyz\"' >/dev/null <<<\"\$J3\"" "invalid firewall_zone + firewalld running: .firewall.zone echoes the configured name"
else
    echo "  (skipping invalid-zone regression: firewalld is not running on this host)"
fi

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

# --- network section ----------------------------------------------------------
assert "jq -e '.network' >/dev/null <<<\"\$J\""                          "has .network"
assert "jq -e '.network.hostname | type == \"string\"' >/dev/null <<<\"\$J\"" "network.hostname is a string"
assert "jq -e '.network.dns | type == \"array\"' >/dev/null <<<\"\$J\""       "network.dns is an array"
assert "jq -e '.network.interfaces | type == \"array\"' >/dev/null <<<\"\$J\"" "network.interfaces is an array"
assert "jq -e '.network | has(\"default\")' >/dev/null <<<\"\$J\""            "network.default present (may be null)"
# default is either null or carries an interface name
assert "jq -e '.network.default == null or (.network.default.iface | type == \"string\")' >/dev/null <<<\"\$J\"" \
       "network.default is null or has an iface"
# every interface entry is fully shaped
assert "jq -e '.network.interfaces | all(has(\"name\") and has(\"kind\") and has(\"up\") and has(\"ip4\") and has(\"ip6\") and has(\"is_default\"))' >/dev/null <<<\"\$J\"" \
       "every interface has the full key set"
assert "jq -e '.network.interfaces | all(.kind | IN(\"ether\",\"wifi\",\"tailnet\",\"virtual\",\"other\"))' >/dev/null <<<\"\$J\"" \
       "every interface kind is from the allowed set"
assert "jq -e '.network.interfaces | all(.ip4 | type == \"array\")' >/dev/null <<<\"\$J\"" "ip4 is always an array"
assert "jq -e '.network.interfaces | map(select(.name == \"lo\")) | length == 0' >/dev/null <<<\"\$J\"" \
       "loopback is excluded"
# exactly one interface may be flagged as the default route
assert "jq -e '[.network.interfaces[] | select(.is_default)] | length <= 1' >/dev/null <<<\"\$J\"" \
       "at most one interface is flagged default"

# --- network.dns: content, not just shape ---------------------------------
# Regression test for a real bug: `net_dns | jq -Rc '[inputs]'` (missing -n)
# silently drops the first resolver line -- on a host with exactly one
# resolver that means an empty array even though DNS is configured and
# net_dns() itself detects it correctly. Extracts the real net_dns() function
# from the shipped CLI (same pattern as the exposure_for_port extraction
# above) so this exercises the real code, not a reimplementation, and stays
# portable: hosts with no resolver at all skip the content assertion instead
# of failing.
(
    eval "$(sed -n '/^net_dns() {/,/^}/p' bin/msw-status)"
    EXPECTED_DNS=$(net_dns)
    if [ -n "$EXPECTED_DNS" ]; then
        assert "jq -e '.network.dns | length > 0' >/dev/null <<<\"\$J\"" \
               "network.dns is non-empty (host has at least one resolver)"
        while IFS= read -r resolver; do
            [ -z "$resolver" ] && continue
            assert "jq -e --arg r \"$resolver\" '.network.dns | index(\$r) != null' >/dev/null <<<\"\$J\"" \
                   "network.dns contains resolver $resolver"
        done <<< "$EXPECTED_DNS"
    else
        echo "  (skipping network.dns content check: no resolver detected on this host)"
    fi
) || exit 1

# --- network.interfaces[].up: recomputed independently from `ip -j addr` ---
# Regression test for a real bug: `up: (.operstate == "UP")` alone
# misclassified tailscale0 (and any tun-type device) as down -- those report
# operstate "UNKNOWN", never "UP", despite being fully usable. The fix adds
# an OR on carrier (LOWER_UP in flags). This recomputes the expected value
# straight from a fresh `ip -j addr` call (not from msw-status's source), so
# it fails loudly if the formula in bin/msw-status regresses, on any machine
# -- not pinned to this host's interface names or addresses.
#
# NOTE on the comparison itself: `$expected[.name] // .up` was tried first and
# rejected -- jq's `//` treats `false` exactly like null/missing, so whenever
# an interface is correctly expected to be DOWN, that expression falls back to
# `.up` and compares the reported value against itself, which can never
# mismatch. That made the check structurally blind to "should be down,
# reported up" -- precisely the virbr0 overcorrection the up-formula fix is
# supposed to guard against. Compare directly instead; a name missing from the
# $expected map is not a real case for the fabricated single-snapshot cases
# below (both sides come from the same synthetic input) and is treated as a
# loud failure there, not silently swallowed.
NET_UP_FILTER='
    ($ip | map({key: .ifname, value: (.operstate == "UP" or ((.flags // []) | index("LOWER_UP") != null))}) | from_entries) as $expected
    | [ $net[] | . as $iface
        | if ($expected | has($iface.name) | not)
          then $iface.name                          # not in the ip -j addr snapshot at all -> fail loudly
          elif $iface.up != $expected[$iface.name]
          then $iface.name                           # formula mismatch, in either direction
          else empty end
      ]
    | length'

# The live check cannot reuse a single `ip -j addr` snapshot taken separately
# from the `msw-status --json` call: `up` is a live kernel property, and on a
# real host it can legitimately change *during* the gap between the two reads
# (e.g. test_power.sh, which runs immediately before this file in the suite,
# toggles wifi off/on -- wlp9s0 then needs a couple of seconds to reassociate
# and come back up). Comparing msw-status's answer against a snapshot read
# before or after it is therefore racy: a perfectly correct implementation can
# disagree with a stale read through no fault of its own. Reproduced directly:
# immediately after `wifi on`, `ip -j addr` and msw-status both agree
# up=false; two seconds later both agree up=true -- the disagreement is
# entirely a timing artifact between two observations, not a formula bug.
#
# Fix: bracket the msw-status call with an `ip -j addr` read BEFORE and AFTER
# it, and assert only on interfaces whose independently computed `up` is
# IDENTICAL in both reads -- those provably did not change state during the
# window, so any disagreement with msw-status's answer for them is a real
# formula bug, not a race. Interfaces that changed (or appeared/disappeared)
# between the two reads are skipped rather than asserted on; the checked/
# skipped counts are always printed so a permanently-flapping interface can
# never silently empty this check without it being visible in the test log.
IP_BEFORE=$(ip -j addr 2>/dev/null); [ -z "$IP_BEFORE" ] && IP_BEFORE="[]"
J_NET=$(bin/msw-status --json)
IP_AFTER=$(ip -j addr 2>/dev/null); [ -z "$IP_AFTER" ] && IP_AFTER="[]"

NET_UP_RESULT=$(jq -n \
    --argjson net "$(jq -c '.network.interfaces' <<<"$J_NET")" \
    --argjson before "$IP_BEFORE" --argjson after "$IP_AFTER" '
    def expected_of($snap): $snap | map({key: .ifname, value: (.operstate == "UP" or ((.flags // []) | index("LOWER_UP") != null))}) | from_entries;
    (expected_of($before)) as $eb
    | (expected_of($after))  as $ea
    | reduce $net[] as $iface ({checked:0, skipped:0, mismatches:[]};
        ($eb[$iface.name]) as $b
        | ($ea[$iface.name]) as $a
        | if ($b == null or $a == null or $b != $a)
          then .skipped += 1
          else (.checked += 1
                | if $iface.up != $b then .mismatches += [$iface.name] else . end)
          end)')
NET_UP_CHECKED=$(jq -r '.checked' <<<"$NET_UP_RESULT")
NET_UP_SKIPPED=$(jq -r '.skipped' <<<"$NET_UP_RESULT")
NET_UP_MISMATCHES=$(jq -r '.mismatches | length' <<<"$NET_UP_RESULT")
echo "  (network.interfaces[].up: checked $NET_UP_CHECKED stable interface(s) across the pre/post read, skipped $NET_UP_SKIPPED unstable)"
# A skip-everything run must not pass quietly: if every interface were unstable
# across the window, `mismatches` would be trivially empty and the assertion
# below would pass having verified nothing -- with only an `echo` as a trace
# that no CI and no reader scanning for FAIL would catch. Assert that the live
# check actually checked something, loudly, as its own assertion.
assert "[ \"$NET_UP_CHECKED\" -gt 0 ]" \
       "network.interfaces[].up live check verified at least one stable interface (checked=$NET_UP_CHECKED skipped=$NET_UP_SKIPPED)"
assert "[ \"$NET_UP_MISMATCHES\" = 0 ]" \
       "every stable interface's up matches operstate==UP or LOWER_UP in flags (checked=$NET_UP_CHECKED skipped=$NET_UP_SKIPPED mismatches=$NET_UP_MISMATCHES)"

# Prove the check above is actually load-bearing in BOTH directions, using
# fabricated snapshots so this does not depend on today's host happening to
# have both an up and a down interface in the right shape. Reuses the exact
# same filter text ($NET_UP_FILTER) so there is no risk of the unit test and
# the live check drifting apart.
(
    # Case A: should be DOWN (operstate DOWN, no LOWER_UP) but msw-status
    # reports up:true -- the virbr0-overcorrection shape. Must be caught.
    N=$(jq -n --argjson net '[{"name":"fakebr","up":true}]' \
              --argjson ip  '[{"ifname":"fakebr","operstate":"DOWN","flags":["BROADCAST"]}]' \
              "$NET_UP_FILTER")
    assert_eq "$N" "1" "up-check catches: should-be-down interface reported up (virbr0 direction)"

    # Case B: should be UP (LOWER_UP present, operstate UNKNOWN, the
    # tailscale0 shape) but msw-status reports up:false. Must be caught.
    N=$(jq -n --argjson net '[{"name":"faketail","up":false}]' \
              --argjson ip  '[{"ifname":"faketail","operstate":"UNKNOWN","flags":["POINTOPOINT","LOWER_UP"]}]' \
              "$NET_UP_FILTER")
    assert_eq "$N" "1" "up-check catches: should-be-up interface reported down (tailscale0 direction)"

    # Case C: both correctly reported -> no false positives.
    N=$(jq -n --argjson net '[{"name":"a","up":true},{"name":"b","up":false}]' \
              --argjson ip  '[{"ifname":"a","operstate":"UP","flags":[]},{"ifname":"b","operstate":"DOWN","flags":[]}]' \
              "$NET_UP_FILTER")
    assert_eq "$N" "0" "up-check: correctly-reported interfaces in both directions produce no mismatch"
) || exit 1

# --- network.interfaces[].kind: deterministic classifier unit test ---------
# Pins the fix round-2 "br0" fix: `test("^(virbr|docker|podman|cni-|veth|br-)")`
# only matched Docker's `br-<hash>` bridges and let a hand-made `br0`-style
# bridge (the conventional name on a VM host, which this project targets) fall
# through and be presented as a physical link. Fixed to `br[0-9-]`. Mirrors the
# classifier in bin/msw-status (keep in sync if that regex changes) and, unlike
# the live host check above, is fully deterministic -- not dependent on this
# machine happening to have a br0-shaped interface -- so the fix cannot
# regress silently.
NET_KIND_FILTER='
    if   ($ifname | startswith("tailscale")) then "tailnet"
    elif ($ifname | test("^(virbr|docker|podman|cni-|veth|br[0-9-])")) then "virtual"
    elif ($ifname | test("^wl")) then "wifi"
    elif ($lt == "ether") then "ether"
    else "other" end'
(
    kind_of() { jq -nr --arg ifname "$1" --arg lt "ether" "$NET_KIND_FILTER"; }

    assert_eq "$(kind_of br0)"              "virtual" "kind: hand-made bridge br0 classifies as virtual"
    assert_eq "$(kind_of br-1a2b3c4d5e6f)"  "virtual" "kind: Docker-style br-<hash> classifies as virtual"
    assert_eq "$(kind_of bridge0)"          "ether"   "kind: bridge0 (unrelated name starting with br) does NOT classify as virtual"
    assert_eq "$(kind_of brcm0)"            "ether"   "kind: brcm0 (unrelated name starting with br) does NOT classify as virtual"
) || exit 1

# --- vnc: who is actually listening -------------------------------------------
assert "jq -e '.remote.vnc | has(\"owner\")' >/dev/null <<<\"\$J\"" "remote.vnc has owner (may be null)"
assert "jq -e '.remote.vnc | has(\"port\")' >/dev/null <<<\"\$J\""  "remote.vnc has port (may be null)"
assert "jq -e '.remote.vnc.active == false or (.remote.vnc.port | type == \"number\")' >/dev/null <<<\"\$J\"" \
       "an active vnc always carries a port number"
assert "jq -e '.remote.vnc.active or (.remote.vnc.owner == null)' >/dev/null <<<\"\$J\"" \
       "an inactive vnc has no owner"

pass
