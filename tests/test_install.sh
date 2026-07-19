#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh

assert "[ -f install.sh ]"   "install.sh exists"
assert "[ -f uninstall.sh ]" "uninstall.sh exists"
assert "[ -f packaging/mobileserverswitch.sudoers ]" "sudoers source exists"

# --- Syntax -----------------------------------------------------------------
bash -n install.sh   || { echo "FAIL: install.sh has a syntax error"; exit 1; }
bash -n uninstall.sh || { echo "FAIL: uninstall.sh has a syntax error"; exit 1; }
bash -n tests/test_install.sh || { echo "FAIL: test_install.sh has a syntax error"; exit 1; }
pass "bash -n install.sh / uninstall.sh / test_install.sh"

# --- --dry-run writes nothing -------------------------------------------------
SANDBOX=$(mktemp -d)
before=$(find "$SANDBOX" | sort)
out=$(HOME="$SANDBOX" XDG_CONFIG_HOME="$SANDBOX/.config" ./install.sh --dry-run --yes 2>&1)
rc=$?
after=$(find "$SANDBOX" | sort)
assert_eq "$rc" "0" "install.sh --dry-run exits 0"
assert_eq "$before" "$after" "install.sh --dry-run creates no files/dirs under \$HOME"
assert "[ ! -e \"$SANDBOX/.local/bin\" ]" "dry-run does not create ~/.local/bin"
assert "[ ! -e \"$SANDBOX/.local/share/plasma/plasmoids/io.github.sunsetterphoto.mobileserverswitch\" ]" "dry-run does not create the plasmoid dir"
assert "[ ! -e \"$SANDBOX/.config/mobileserverswitch\" ]" "dry-run does not create the config dir"
rm -rf "$SANDBOX"

# --- --dry-run lists the expected actions/paths -------------------------------
assert "grep -q 'kpackagetool6 --type Plasma/Applet' <<<\"\$out\"" "lists the plasmoid action"
assert "grep -q 'io.github.sunsetterphoto.mobileserverswitch' <<<\"\$out\"" "lists the plasmoid id/path"
assert "grep -q '.local/bin' <<<\"\$out\"" "lists the CLI (~/.local/bin) target"
assert "grep -q '/usr/local/sbin' <<<\"\$out\"" "lists the helper (/usr/local/sbin) target"
assert "grep -q '/etc/sudoers.d/mobileserverswitch' <<<\"\$out\"" "lists the sudoers target"
assert "grep -q 'config/config.example.json' <<<\"\$out\"" "lists the default-config action"
assert "grep -qi 'dry-run' <<<\"\$out\"" "explicitly marks itself as a dry-run"
pass "install.sh --dry-run lists the correct actions/paths"

# --- --no-sudoers skips the sudoers section entirely --------------------------
out2=$(HOME=$(mktemp -d) ./install.sh --dry-run --no-sudoers 2>&1)
assert "grep -q 'Skipped (--no-sudoers)' <<<\"\$out2\"" "--no-sudoers is honored"
pass "install.sh --no-sudoers skips the sudoers step"

# --- Generated sudoers content: exactly the 4 helper paths, nothing else -----
# Only the active (non-comment, non-blank) line matters for the grant itself;
# comments are documentation and may legitimately mention "ssh"/"systemctl"
# (as things that are *not* granted) and the literal "__USER__" placeholder
# token -- mirror install.sh's awk substitution (comments untouched, only the
# active line gets the real user substituted in).
GENERATED=$(awk -v u="testuser" '
    /^[[:space:]]*#/ { print; next }
    { gsub(/__USER__/, u); print }
' packaging/mobileserverswitch.sudoers)
ACTIVE=$(grep -vE '^[[:space:]]*(#|$)' <<<"$GENERATED")
assert "grep -qF 'testuser ALL=(root) NOPASSWD:' <<<\"\$ACTIVE\"" "sudoers grants NOPASSWD to the substituted user"
for h in msw-charge-apply msw-perf-apply msw-power-apply msw-firewall-apply; do
    assert "grep -qF '/usr/local/sbin/$h' <<<\"\$ACTIVE\"" "sudoers lists $h"
done
# Exactly one active (non-comment) line, and nothing else granted on it: no
# ssh, no wildcard paths, no systemctl, and exactly 4 "/usr/local/sbin/"
# occurrences (one per helper).
assert_eq "$(wc -l <<<"$ACTIVE")" "1" "sudoers has exactly one active grant line"
assert "! grep -qiE 'ssh|systemctl|/bin/bash|\*' <<<\"\$ACTIVE\"" "sudoers grant has no ssh/systemctl/wildcard/shell entries"
count=$(grep -o '/usr/local/sbin/[a-zA-Z0-9_-]*' <<<"$ACTIVE" | sort -u | wc -l)
assert_eq "$count" "4" "sudoers lists exactly 4 distinct helper paths"
assert "! grep -qF '__USER__' <<<\"\$ACTIVE\"" "placeholder is substituted on the active grant line"
pass "generated sudoers content is exactly the 4 helper paths"

# --- The repo file itself must never contain a real username ------------------
assert "! grep -qiE 'samuel' packaging/mobileserverswitch.sudoers" "repo sudoers file has no hardcoded personal username"
assert "grep -qF '__USER__' packaging/mobileserverswitch.sudoers" "repo sudoers file uses the __USER__ placeholder"
pass "repo sudoers file is de-personalized"

# --- uninstall.sh --dry-run also writes/removes nothing -----------------------
SANDBOX2=$(mktemp -d)
before2=$(find "$SANDBOX2" | sort)
out3=$(HOME="$SANDBOX2" ./uninstall.sh --dry-run 2>&1)
rc3=$?
after2=$(find "$SANDBOX2" | sort)
assert_eq "$rc3" "0" "uninstall.sh --dry-run exits 0"
assert_eq "$before2" "$after2" "uninstall.sh --dry-run changes nothing under \$HOME"
assert "grep -qi 'dry-run' <<<\"\$out3\"" "uninstall.sh --dry-run marks itself as a dry-run"
rm -rf "$SANDBOX2"
pass "uninstall.sh --dry-run is a no-op"

pass
