# Minimal assertion helpers for this repo's shell tests.
assert()    { if ! eval "$1"; then echo "FAIL: $2 ( $1 )"; exit 1; fi; }
assert_eq() { if [ "$1" != "$2" ]; then echo "FAIL: $3 (expected '$2', got '$1')"; exit 1; fi; }
pass()      { echo "PASS: ${1:-$(basename "$0")}"; }
