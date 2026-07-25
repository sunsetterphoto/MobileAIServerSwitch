# MobileAIServerSwitch — packaging convenience targets.
# Everything here is optional; install.sh/uninstall.sh do not depend on it.

PLASMOID_ID  := io.github.sunsetterphoto.mobileserverswitch
PLASMOID_DIR := plasmoid/$(PLASMOID_ID)

.PHONY: package clean test

# package — build a .plasmoid archive for distribution. The .plasmoid format
# is just a zip of the plasmoid directory (this Plasma 6's kpackagetool6 has
# no --package/--output option -- only install/upgrade/remove/list/show/hash
# -- so plain zip is the actual mechanism, not a fallback).
package: $(PLASMOID_ID).plasmoid

$(PLASMOID_ID).plasmoid: $(shell find $(PLASMOID_DIR) -type f)
	rm -f "$@"
	command -v zip >/dev/null 2>&1 || { echo "zip not found -- required to build a .plasmoid" >&2; exit 1; }
	( cd plasmoid && zip -r -X "../$@" "$(PLASMOID_ID)" )
	@echo "Built: $@"

clean:
	rm -f $(PLASMOID_ID).plasmoid

test:
	for t in tests/test_*.sh; do bash "$$t" || exit 1; done
