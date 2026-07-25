#!/usr/bin/env bash
# msw-notes: read/write of the notes file. Runs entirely against a temporary
# MSW_NOTES_FILE -- the user's real notes are never touched.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
CLI=bin/msw-notes

TMPDIR_T=$(mktemp -d)
trap 'rm -rf "$TMPDIR_T"' EXIT
export MSW_NOTES_FILE="$TMPDIR_T/notes.md"

b64() { printf '%s' "$1" | base64 -w0; }
run() { "$CLI" "$@" >/dev/null 2>&1; echo $?; }

assert "[ -x $CLI ]" "msw-notes is executable"

# --- missing file behaves like an empty one ----------------------------------
assert_eq "$($CLI read)"  ""  "read on a missing file yields empty output"
assert_eq "$(run read)"   "0" "read on a missing file exits 0"
assert_eq "$($CLI mtime)" "0" "mtime on a missing file is 0"
assert "[ \"$($CLI path)\" = \"$MSW_NOTES_FILE\" ]" "path prints the notes file location"

# --- round trip ---------------------------------------------------------------
TEXT='# Server notes
ComfyUI runs on :8188 — "remember" this & that\
tab	separated, trailing spaces   '
$CLI write --base64 "$(b64 "$TEXT")" >/dev/null
assert_eq "$($CLI read)" "$TEXT" "round trip preserves the text exactly"

# --- permissions --------------------------------------------------------------
assert_eq "$(stat -c '%a' "$MSW_NOTES_FILE")" "600" "notes file is mode 600"

# --- mtime advances -----------------------------------------------------------
M1=$($CLI mtime)
sleep 1
$CLI write --base64 "$(b64 "changed")" >/dev/null
assert "[ \"$($CLI mtime)\" -gt \"$M1\" ]" "mtime advances after a write"
assert_eq "$($CLI read)" "changed" "second write replaced the content"

# --- bad invocation changes nothing -------------------------------------------
assert_eq "$(run)"                       "2" "no subcommand -> exit 2"
assert_eq "$(run bogus)"                 "2" "unknown subcommand -> exit 2"
assert_eq "$(run write)"                 "2" "write without data -> exit 2"
assert_eq "$(run write --base64)"        "2" "write with a missing value -> exit 2"
assert_eq "$(run write --base64 'not!base64!')" "2" "invalid base64 -> exit 2"
assert_eq "$($CLI read)" "changed"       "a rejected write left the file untouched"

# --- unicode ------------------------------------------------------------------
U='Grüße 🚀 日本語'
$CLI write --base64 "$(b64 "$U")" >/dev/null
assert_eq "$($CLI read)" "$U" "unicode survives the round trip"

# --- byte-exact round trip ------------------------------------------------------
# Regression coverage: an earlier draft decoded base64 into a shell variable
# via $(...) command substitution, which silently strips ALL trailing
# newlines (and cannot hold embedded NULs at all), corrupting any note that
# ends with a blank line. Ordinary `$($CLI read)` string comparison would
# hide that exact bug HERE TOO (bash strips trailing newlines from command
# substitution in the test itself), so these compare raw files with cmp/
# wc -c, never `$($CLI read)`.
roundtrip_bytes() {
    # $1 = fixture file with the exact expected bytes, $2 = description
    local expected="$1" desc="$2" actual="$TMPDIR_T/actual.bin"
    "$CLI" write --base64 "$(base64 -w0 "$expected")" >/dev/null
    "$CLI" read > "$actual"
    assert_eq "$(wc -c < "$actual")" "$(wc -c < "$expected")" "$desc (byte count matches)"
    assert "cmp -s \"$actual\" \"$expected\"" "$desc (byte-exact via cmp)"
}

printf 'single trailing newline\n' > "$TMPDIR_T/fx_single_nl.bin"
roundtrip_bytes "$TMPDIR_T/fx_single_nl.bin" "text ending in a single trailing newline"

printf 'several blank lines follow\n\n\n\n' > "$TMPDIR_T/fx_multi_nl.bin"
roundtrip_bytes "$TMPDIR_T/fx_multi_nl.bin" "text ending in several blank lines"

printf '\n\n\n\n\n' > "$TMPDIR_T/fx_only_nl.bin"
roundtrip_bytes "$TMPDIR_T/fx_only_nl.bin" "text consisting only of newlines"

printf 'no trailing newline at all' > "$TMPDIR_T/fx_no_nl.bin"
roundtrip_bytes "$TMPDIR_T/fx_no_nl.bin" "text with no trailing newline at all (fix must not overcorrect)"

# --- no leftover temp files ---------------------------------------------------
assert_eq "$(find "$TMPDIR_T" -name '.notes.md.*' | wc -l)" "0" "no temp files left behind"
pass
