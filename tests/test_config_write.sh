#!/usr/bin/env bash
# Test of bin/msw-config-write: the settings UI's only write path into
# config.json. Uses a throwaway MSW_CONFIG_FILE (a temp directory), never the
# real ~/.config/mobileserverswitch/config.json -- msw-config-write itself
# has no test-only override besides that env var (see bin/msw-config), same
# mechanism test_config.sh already relies on.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

CFG_DIR="$WORKDIR/mobileserverswitch"
CFG_FILE="$CFG_DIR/config.json"
export MSW_CONFIG_FILE="$CFG_FILE"

# --- fresh write: target dir doesn't even exist yet -----------------------------
printf '%s' '{"services":[{"id":"a"}]}' | bin/msw-config-write
assert_eq "$?" "0" "fresh write (no existing dir/file) exits 0"
assert "[ -f \"\$CFG_FILE\" ]" "config.json was created"
assert "jq -e . \"\$CFG_FILE\" >/dev/null 2>&1" "written file is valid JSON"
assert_eq "$(jq -r '.services[0].id' "$CFG_FILE")" "a" "written file matches stdin input"

# --- rejects malformed JSON: exit != 0, existing file untouched -----------------
before=$(cat "$CFG_FILE")
printf '%s' '{not valid json' | bin/msw-config-write 2>/dev/null
code=$?
assert "[ \"\$code\" -ne 0 ]" "malformed JSON input exits non-zero (got $code)"
assert_eq "$(cat "$CFG_FILE")" "$before" "existing config.json is untouched after malformed input"

# --- rejects non-object JSON (array/scalar): exit != 0, existing file untouched -
printf '%s' '[1,2,3]' | bin/msw-config-write 2>/dev/null
code=$?
assert "[ \"\$code\" -ne 0 ]" "non-object JSON (array) input exits non-zero (got $code)"
assert_eq "$(cat "$CFG_FILE")" "$before" "existing config.json is untouched after non-object input"

printf '%s' '"just a string"' | bin/msw-config-write 2>/dev/null
code=$?
assert "[ \"\$code\" -ne 0 ]" "non-object JSON (scalar) input exits non-zero (got $code)"
assert_eq "$(cat "$CFG_FILE")" "$before" "existing config.json is untouched after scalar input"

# --- atomic: no leftover temp file in the config dir after a rejected write -----
leftover=$(find "$CFG_DIR" -maxdepth 1 -name '.config.json.*' 2>/dev/null)
assert_eq "$leftover" "" "no partial/leftover temp file remains in $CFG_DIR after rejection"

# --- deep-merge: unknown keys (e.g. network.wol_nic) survive a later write ------
#     that only sends a different top-level key (services).
cat > "$CFG_FILE" <<'JSON'
{ "network": { "lan_interfaces": "auto", "wol_nic": "eth7" }, "services": [ { "id": "old" } ] }
JSON

printf '%s' '{"services":[{"id":"new"}]}' | bin/msw-config-write
assert_eq "$?" "0" "merge write exits 0"
assert_eq "$(jq -r '.network.wol_nic' "$CFG_FILE")" "eth7" "unknown key network.wol_nic survives a write that doesn't mention it"
assert_eq "$(jq -r '.network.lan_interfaces' "$CFG_FILE")" "auto" "unrelated known key network.lan_interfaces also survives"
# services is an ARRAY -- replaced wholesale by the incoming value, not
# concatenated/merged element-by-element.
assert_eq "$(jq -c '.services' "$CFG_FILE")" '[{"id":"new"}]' "services array is replaced wholesale, not merged/appended"

pass
