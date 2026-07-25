#!/usr/bin/env bash
# The user-visible product name must be consistent. Identifiers and paths
# (plasmoid ID, msw-* CLIs, /var/lib, ~/.config, sudoers) deliberately keep
# the old name -- see the design spec; this test pins that split down.
set -uo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh

NAME="Mobile AI Server Switch"

assert "grep -q '\"Name\": \"$NAME\"' plasmoid/*/metadata.json" "metadata Name is '$NAME'"
assert "grep -q '$NAME' README.md"        "README uses the new name"
assert "grep -q '$NAME' docs/index.html"  "Pages site uses the new name"

# No stale user-visible occurrences of the old product name
assert "! grep -rn 'Mobile Server Switch' README.md docs/index.html CONTRIBUTING.md plasmoid/ 2>/dev/null | grep -q ." \
       "no user-visible occurrence of the old product name remains"

# Identifiers must NOT have been renamed along the way
assert "grep -q 'io.github.sunsetterphoto.mobileserverswitch' plasmoid/*/metadata.json" "plasmoid ID unchanged"
assert "[ -f packaging/mobileserverswitch.sudoers ]"                                    "sudoers filename unchanged"
assert "grep -q '/var/lib/mobileserverswitch' bin/msw-mode"                             "state path unchanged"
assert "grep -q 'mobileserverswitch/config.json' bin/msw-config"                        "config path unchanged"
pass
