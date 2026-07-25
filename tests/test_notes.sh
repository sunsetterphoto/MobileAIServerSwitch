#!/usr/bin/env bash
# msw-notes: read/write of the notes file. Runs entirely against a temporary
# MSW_NOTES_FILE -- the user's real notes are never touched.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
CLI=bin/msw-notes

TMPDIR_T=$(mktemp -d)
# chmod restore BEFORE rm -rf: a chmod-000 fixture inside $TMPDIR_T does not
# actually block `rm -rf` (unlink only needs write+execute on the *parent*
# directory, which we own), but the chmod restore is cheap, unconditional
# (fires on ANY exit -- normal completion or an assertion's early `exit 1`),
# and means nothing mode-000 is ever left behind even if some later change
# to this script or its fixtures made that assumption stop holding.
trap 'chmod -R u+rwX "$TMPDIR_T" 2>/dev/null; rm -rf "$TMPDIR_T"' EXIT
export MSW_NOTES_FILE="$TMPDIR_T/notes.md"

b64() { printf '%s' "$1" | base64 -w0; }
run() { "$CLI" "$@" >/dev/null 2>&1; echo $?; }

assert "[ -x $CLI ]" "msw-notes is executable"

# --- missing file behaves like an empty one ----------------------------------
assert_eq "$($CLI read 2>/dev/null)"  ""  "read on a missing file yields empty output"
assert_eq "$(run read)"   "0" "read on a missing file exits 0"
assert_eq "$($CLI mtime)" "0" "mtime on a missing file is 0"
assert "[ \"$($CLI path)\" = \"$MSW_NOTES_FILE\" ]" "path prints the notes file location"

# read also reports "MTIME:<epoch>" on stderr on every exit-0 outcome (missing
# file included), read in the SAME invocation as the content -- this is what
# lets the widget adopt loadedMtime without a second, separate `mtime` call
# that could itself race an external writer (see NotesTab.qml).
R_ERR=$($CLI read 2>&1 >/dev/null)
assert_eq "$R_ERR" "MTIME:0" "read on a missing file reports MTIME:0 on stderr"

# --- an existing-but-unreadable file must NOT look like a missing one --------
# Regression test for the CRITICAL bug this fix closes: `[ -r "$NOTES_FILE" ]
# && cat ...; exit 0` made an UNREADABLE file (the realistic trigger: it ends
# up root-owned after `sudo $EDITOR` over SSH) indistinguishable from a
# MISSING one -- both read as "" with exit 0. The widget then showed an empty,
# editable pad; the user typed into it; the debounce save's freshness check
# saw no conflict (mtime still worked fine -- stat only needs directory
# traversal, not file read permission); and `mv -f` (which only needs
# directory write permission, not file read permission) silently destroyed
# the real content. `chmod 000` here is cleaned up by the script-wide EXIT
# trap at the top (chmod -R u+rwX, then rm -rf), which fires even if an
# assertion below exits the script early.
UNREADABLE_FILE="$TMPDIR_T/unreadable.md"
printf 'root-owned content -- must survive' > "$UNREADABLE_FILE"
chmod 000 "$UNREADABLE_FILE"
UR_STDOUT=$(MSW_NOTES_FILE="$UNREADABLE_FILE" "$CLI" read 2>/dev/null)
UR_CODE=$(MSW_NOTES_FILE="$UNREADABLE_FILE" "$CLI" read >/dev/null 2>&1; echo $?)
UR_STDERR=$(MSW_NOTES_FILE="$UNREADABLE_FILE" "$CLI" read 2>&1 >/dev/null)
assert_eq "$UR_STDOUT" "" "read on an unreadable file prints nothing on stdout (never adopted as empty content)"
assert_eq "$UR_CODE"   "1" "read on an unreadable file exits 1, not 0 (distinguishable from missing)"
assert "[ -n \"$UR_STDERR\" ]" "read on an unreadable file explains itself on stderr"
# mtime is a separate, unprivileged path (stat needs only directory
# traversal) and stays untouched by this fix -- it still reports the real
# mtime, proving the file is still there, not silently gone.
UR_MTIME=$(MSW_NOTES_FILE="$UNREADABLE_FILE" "$CLI" mtime)
assert "[ \"$UR_MTIME\" -gt 0 ]" "mtime still reports the unreadable file's real mtime"
chmod 600 "$UNREADABLE_FILE"
assert_eq "$(MSW_NOTES_FILE="$UNREADABLE_FILE" $CLI read 2>/dev/null)" "root-owned content -- must survive" \
       "once readable again, the content -- never touched while unreadable -- is exactly what was there before"

# --- a directory at the notes path is the same root cause --------------------
DIR_AS_NOTES="$TMPDIR_T/dir-notes.md"
mkdir -p "$DIR_AS_NOTES"
DA_STDOUT=$(MSW_NOTES_FILE="$DIR_AS_NOTES" "$CLI" read 2>/dev/null)
DA_CODE=$(MSW_NOTES_FILE="$DIR_AS_NOTES" "$CLI" read >/dev/null 2>&1; echo $?)
DA_STDERR=$(MSW_NOTES_FILE="$DIR_AS_NOTES" "$CLI" read 2>&1 >/dev/null)
assert_eq "$DA_STDOUT" "" "read against a directory prints nothing on stdout"
assert_eq "$DA_CODE"   "1" "read against a directory exits 1, not 0"
assert "[ -n \"$DA_STDERR\" ]" "read against a directory explains itself on stderr"

# --- round trip ---------------------------------------------------------------
TEXT='# Server notes
ComfyUI runs on :8188 — "remember" this & that\
tab	separated, trailing spaces   '
$CLI write --base64 "$(b64 "$TEXT")" >/dev/null
assert_eq "$($CLI read 2>/dev/null)" "$TEXT" "round trip preserves the text exactly"

# On the common (readable-file) success path, read's own MTIME:<epoch> on
# stderr matches a fresh, separate `mtime` call -- pinning that the
# single-invocation value is not just plausible-looking but actually correct.
RT_ERR=$($CLI read 2>&1 >/dev/null)
assert_eq "$RT_ERR" "MTIME:$($CLI mtime)" \
    "read's stderr mtime for an existing file matches a fresh mtime call"

# --- permissions --------------------------------------------------------------
assert_eq "$(stat -c '%a' "$MSW_NOTES_FILE")" "600" "notes file is mode 600"

# --- mtime advances -----------------------------------------------------------
M1=$($CLI mtime)
sleep 1
$CLI write --base64 "$(b64 "changed")" >/dev/null
assert "[ \"$($CLI mtime)\" -gt \"$M1\" ]" "mtime advances after a write"
assert_eq "$($CLI read 2>/dev/null)" "changed" "second write replaced the content"

# --- bad invocation changes nothing -------------------------------------------
assert_eq "$(run)"                       "2" "no subcommand -> exit 2"
assert_eq "$(run bogus)"                 "2" "unknown subcommand -> exit 2"
assert_eq "$(run write)"                 "2" "write without data -> exit 2"
assert_eq "$(run write --base64)"        "2" "write with a missing value -> exit 2"
assert_eq "$(run write --base64 'not!base64!')" "2" "invalid base64 -> exit 2"
assert_eq "$($CLI read 2>/dev/null)" "changed"       "a rejected write left the file untouched"

# --- write prints the mtime it just set (no second round trip needed) ---------
# This is what the plasmoid's conflict guard relies on: adopting the mtime
# from write's own stdout instead of issuing a separate `mtime` call closes
# the race window where an external writer could land between the two calls
# and get silently mistaken for "our" write.
W_OUT=$($CLI write --base64 "$(b64 "printed mtime")")
assert "echo \"$W_OUT\" | grep -qE '^[0-9]+\$'" "write prints a single numeric mtime line"
assert_eq "$W_OUT" "$($CLI mtime)" "the mtime write prints matches a fresh mtime call"
assert_eq "$($CLI read 2>/dev/null)" "printed mtime" "content from the mtime-printing write round-trips"

# --- unicode ------------------------------------------------------------------
U='Grüße 🚀 日本語'
$CLI write --base64 "$(b64 "$U")" >/dev/null
assert_eq "$($CLI read 2>/dev/null)" "$U" "unicode survives the round trip"

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
    "$CLI" read 2>/dev/null > "$actual"
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
