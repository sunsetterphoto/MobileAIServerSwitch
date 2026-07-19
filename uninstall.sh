#!/usr/bin/env bash
# uninstall.sh — reverses install.sh: removes the plasmoid, the CLIs, the
# privileged helpers, the optional systemd unit and the scoped sudoers file.
# The user config (~/.config/mobileserverswitch/config.json) is left in
# place unless --purge is given.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
cd "$REPO_ROOT"

PLASMOID_ID="io.github.sunsetterphoto.mobileserverswitch"
PLASMOID_DST="$HOME/.local/share/plasma/plasmoids/$PLASMOID_ID"
BIN_DST="$HOME/.local/bin"
SBIN_DST="/usr/local/sbin"
SYSTEMD_DST="/etc/systemd/system"
SYSTEMD_UNIT="msw-charge-thresholds.service"
SUDOERS_DST="/etc/sudoers.d/mobileserverswitch"
CONFIG_DST="${XDG_CONFIG_HOME:-$HOME/.config}/mobileserverswitch/config.json"
CONFIG_DIR="$(dirname "$CONFIG_DST")"

DRY_RUN=0
PURGE=0

usage() {
    cat <<'EOF'
Usage: uninstall.sh [options]

  --dry-run   Print every action that would be taken; remove nothing.
  --purge     Also remove the user config directory
              (~/.config/mobileserverswitch/).
  -h, --help  Show this help.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --purge) PURGE=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

log()  { printf '%s\n' "$*"; }
step() { printf '\n== %s ==\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }

rm_file() {  # rm_file <path> [root]
    local path=$1 root=${2:-0}
    [ -e "$path" ] || { log "  (absent) $path"; return 0; }
    if [ "$root" = 1 ]; then
        log "  [sudo] rm -f $path"
        [ "$DRY_RUN" = 1 ] && return 0
        sudo rm -f "$path"
    else
        log "  rm -f $path"
        [ "$DRY_RUN" = 1 ] && return 0
        rm -f "$path"
    fi
}

[ "$DRY_RUN" = 1 ] && log "*** --dry-run: nothing will be removed ***"

# --- Plasmoid ----------------------------------------------------------------
step "Plasmoid ($PLASMOID_ID)"
if command -v kpackagetool6 >/dev/null 2>&1; then
    if [ -d "$PLASMOID_DST" ] || kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -qF "$PLASMOID_ID"; then
        log "  kpackagetool6 --type Plasma/Applet --remove $PLASMOID_ID"
        [ "$DRY_RUN" = 0 ] && kpackagetool6 --type Plasma/Applet --remove "$PLASMOID_ID"
    else
        log "  (not installed) $PLASMOID_ID"
    fi
else
    warn "kpackagetool6 not found -- cannot remove the plasmoid registration. Directory left as-is: $PLASMOID_DST"
fi

# --- CLIs ----------------------------------------------------------------
step "CLIs ($BIN_DST)"
for f in bin/*; do
    [ -f "$f" ] || continue
    rm_file "$BIN_DST/$(basename "$f")" 0
done

# --- Privileged helpers ----------------------------------------------------
step "Privileged helpers ($SBIN_DST, root)"
for f in system/usr-local-sbin/*; do
    [ -f "$f" ] || continue
    rm_file "$SBIN_DST/$(basename "$f")" 1
done

# --- systemd unit --------------------------------------------------------------
step "systemd unit ($SYSTEMD_UNIT)"
if [ -e "$SYSTEMD_DST/$SYSTEMD_UNIT" ]; then
    log "  [sudo] systemctl disable --now $SYSTEMD_UNIT"
    [ "$DRY_RUN" = 0 ] && sudo systemctl disable --now "$SYSTEMD_UNIT" 2>/dev/null || true
    rm_file "$SYSTEMD_DST/$SYSTEMD_UNIT" 1
    log "  [sudo] systemctl daemon-reload"
    [ "$DRY_RUN" = 0 ] && sudo systemctl daemon-reload
else
    log "  (absent) $SYSTEMD_DST/$SYSTEMD_UNIT"
fi

# --- Sudoers -------------------------------------------------------------------
step "Scoped sudoers"
rm_file "$SUDOERS_DST" 1

# --- User config -----------------------------------------------------------
step "User config"
if [ "$PURGE" = 1 ]; then
    if [ -d "$CONFIG_DIR" ]; then
        log "  rm -rf $CONFIG_DIR"
        [ "$DRY_RUN" = 0 ] && rm -rf "$CONFIG_DIR"
    else
        log "  (absent) $CONFIG_DIR"
    fi
else
    log "  Left in place: $CONFIG_DST (pass --purge to remove it)"
fi

step "Done"
[ "$DRY_RUN" = 1 ] && log "(dry-run: nothing was removed)"
log "Reload the plasmoid: kquitapp6 plasmashell && kstart plasmashell  (or log out/in)"
exit 0
