#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
assert "[ -x scripts/sync.sh ]" "sync.sh exists and is executable"
# --dry-run must write nothing and must list the 4 target classes
SANDBOX=$(mktemp -d)
out=$(HOME="$SANDBOX" scripts/sync.sh --dry-run 2>&1)
assert "grep -q 'plasmoids/io.github.sunsetterphoto.mobileserverswitch' <<<\"\$out\"" "lists the plasmoid target"
assert "grep -q '.local/bin' <<<\"\$out\"" "lists the bin target"
assert "grep -q '/usr/local/sbin' <<<\"\$out\"" "lists the sbin target"
assert "[ ! -d \"$SANDBOX/.local/bin\" ]" "dry-run does not write .local/bin"
assert "[ ! -d \"$SANDBOX/.local/share/plasma/plasmoids/io.github.sunsetterphoto.mobileserverswitch\" ]" "dry-run does not write the plasmoid"
rm -rf "$SANDBOX"
pass
