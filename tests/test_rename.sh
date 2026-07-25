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

# No stale user-visible occurrences of the old product name, anywhere in the
# tracked tree -- not a hand-picked file list. A hand-picked list is exactly
# what let a reverted rename slip through undetected once already: install.sh
# had a stray "Mobile Server Switch" restored and this test still printed
# PASS, because install.sh was never one of the files it looked at. `git
# grep` walks every tracked file instead, so no file can be quietly outside
# its reach again. This test's own literal pattern below (and NAME above) IS
# itself an occurrence of the string being searched for -- it is the ONE
# deliberate, permitted exception (the identifiers listed in the file header
# -- the plasmoid ID, the msw- prefix, /var/lib/..., ~/.config/..., the
# sudoers filename, the systemd unit name -- are already safe without any
# exclusion, since none of them contain "Mobile Server Switch" as a literal
# substring: they are lowercase and spaceless, this pattern is not).
assert "! git grep -qn --fixed-strings 'Mobile Server Switch' -- . ':!tests/test_rename.sh'" \
       "no user-visible occurrence of the old product name remains anywhere in the tracked tree"

# Identifiers must NOT have been renamed along the way
assert "grep -q 'io.github.sunsetterphoto.mobileserverswitch' plasmoid/*/metadata.json" "plasmoid ID unchanged"
assert "[ -f packaging/mobileserverswitch.sudoers ]"                                    "sudoers filename unchanged"
assert "grep -q '/var/lib/mobileserverswitch' bin/msw-mode"                             "state path unchanged"
assert "grep -q 'mobileserverswitch/config.json' bin/msw-config"                        "config path unchanged"
pass
