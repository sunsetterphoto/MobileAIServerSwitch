#!/usr/bin/env bash
# Deploys this repo's versioned files to their live paths.
# Idempotent. --dry-run only shows what would happen.
#
# This is the lightweight dev-deploy loop (copy-only, no dependency checks,
# no sudoers, no consent prompts, assumes the plasmoid is already
# registered). For a first-time/full install on a new machine -- dependency
# checks, plasmoid registration, the scoped sudoers grant, default config --
# use install.sh at the repo root instead.
set -euo pipefail
cd "$(dirname "$0")/.."
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1

do_cp() {  # do_cp <source> <dest> <mode> [sudo]
    local src=$1 dst=$2 mode=$3 pre=""; [ "${4:-}" = "sudo" ] && pre="sudo -n"
    echo "  $src -> $dst (mode $mode${4:+, root})"
    [ "$DRY" = 1 ] && return 0
    $pre install -D -m "$mode" "$src" "$dst"
}

echo "Plasmoid:"
# Sync the plasmoid as a whole directory (rsync-free, cp -a)
PLASMO_DST="$HOME/.local/share/plasma/plasmoids/io.github.sunsetterphoto.mobileserverswitch"
echo "  plasmoid/io.github.sunsetterphoto.mobileserverswitch -> $PLASMO_DST"
if [ "$DRY" = 0 ] && [ -d plasmoid/io.github.sunsetterphoto.mobileserverswitch ]; then
    mkdir -p "$PLASMO_DST"
    cp -a plasmoid/io.github.sunsetterphoto.mobileserverswitch/. "$PLASMO_DST/"
fi
echo "bin (.local/bin):"
for f in bin/*; do [ -f "$f" ] && do_cp "$f" "$HOME/.local/bin/$(basename "$f")" 755; done
echo "system/usr-local-sbin (/usr/local/sbin, root):"
for f in system/usr-local-sbin/*; do [ -f "$f" ] && do_cp "$f" "/usr/local/sbin/$(basename "$f")" 755 sudo; done
echo "system/systemd (/etc/systemd/system, root):"
for f in system/systemd/*.service; do [ -f "$f" ] && do_cp "$f" "/etc/systemd/system/$(basename "$f")" 644 sudo; done

if [ "$DRY" = 0 ]; then
    # DELIBERATELY NOT `kpackagetool6 --upgrade "$PLASMO_DST"`: since source ==
    # destination (the install dir), kpackagetool6 would delete the destination
    # first as part of the atomic replace -> the plasmoid would be gone (a bug
    # hit by early sync.sh versions). The `cp -a` above already deploys
    # everything; changes take effect after a plasmashell reload. (First-time
    # registration for "Add Widgets" is a one-off manual step:
    #  kpackagetool6 --type Plasma/Applet --install plasmoid/io.github.sunsetterphoto.mobileserverswitch)
    echo "Done. Reload the plasmoid: kquitapp6 plasmashell && kstart plasmashell  (or log out/in)"
fi
