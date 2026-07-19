#!/usr/bin/env bash
# install.sh — installs Mobile Server Switch onto this system: the plasmoid,
# the 6 CLIs, the 4 privileged apply helpers, an optional systemd unit, a
# scoped sudoers grant (opt-in, consent-gated) and a default config.
# Idempotent (safe to re-run). See uninstall.sh for the reverse, and
# scripts/sync.sh for the lighter-weight dev-deploy loop this installer's
# path knowledge mirrors.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
cd "$REPO_ROOT"

PLASMOID_ID="io.github.sunsetterphoto.mobileserverswitch"
PLASMOID_SRC="$REPO_ROOT/plasmoid/$PLASMOID_ID"
PLASMOID_DST="$HOME/.local/share/plasma/plasmoids/$PLASMOID_ID"
BIN_DST="$HOME/.local/bin"
SBIN_DST="/usr/local/sbin"
SYSTEMD_DST="/etc/systemd/system"
SUDOERS_SRC="$REPO_ROOT/packaging/mobileserverswitch.sudoers"
SUDOERS_DST="/etc/sudoers.d/mobileserverswitch"
CONFIG_DST="${XDG_CONFIG_HOME:-$HOME/.config}/mobileserverswitch/config.json"

DRY_RUN=0
NO_SUDOERS=0
ASSUME_YES=0
WITH_CHARGE_SERVICE=0

usage() {
    cat <<'EOF'
Usage: install.sh [options]

  --dry-run              Print every action that would be taken; write/change nothing.
  --no-sudoers            Skip the scoped sudoers file entirely (no prompt either).
  --yes                   Assume "yes" at the sudoers consent prompt (non-interactive).
  --with-charge-service   Also install msw-charge-thresholds.service (opt-in, not enabled).
  -h, --help              Show this help.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --no-sudoers) NO_SUDOERS=1 ;;
        --yes) ASSUME_YES=1 ;;
        --with-charge-service) WITH_CHARGE_SERVICE=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

log()  { printf '%s\n' "$*"; }
step() { printf '\n== %s ==\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# install_file <src> <dst> <mode> [root]  — print the action; perform it
# unless --dry-run.
install_file() {
    local src=$1 dst=$2 mode=$3 root=${4:-0}
    if [ "$root" = 1 ]; then
        log "  [sudo] install -D -m $mode $src -> $dst"
        [ "$DRY_RUN" = 1 ] && return 0
        sudo install -D -m "$mode" "$src" "$dst"
    else
        log "  install -D -m $mode $src -> $dst"
        [ "$DRY_RUN" = 1 ] && return 0
        install -D -m "$mode" "$src" "$dst"
    fi
}

[ "$DRY_RUN" = 1 ] && log "*** --dry-run: no files will be created/changed, no commands with side effects will run ***"

# --- Dependencies -----------------------------------------------------------
step "Dependencies"
MISSING_REQUIRED=0
for c in jq kpackagetool6; do
    if command -v "$c" >/dev/null 2>&1; then
        log "  OK       $c"
    else
        log "  MISSING  $c (required)"
        MISSING_REQUIRED=1
    fi
done
[ "$MISSING_REQUIRED" = 0 ] || die "required dependency missing (see above) -- install it and re-run."

check_optional() {  # check_optional <cmd> <feature description>
    if command -v "$1" >/dev/null 2>&1; then
        log "  OK       $1"
    else
        warn "$1 not found -- $2 will be unavailable."
    fi
}
check_optional firewall-cmd     "LAN firewall blocking (Firewall tab)"
check_optional rfkill           "WiFi/Bluetooth radio switches"
check_optional ethtool          "Wake-on-LAN status/control"
check_optional tailscale        "Tailnet status/IP detection"
check_optional powerprofilesctl "performance-profile CLI diagnostics (msw-perf itself uses D-Bus directly and is unaffected)"
check_optional nvidia-smi       "dGPU power-draw reporting"

# --- Distro (informational only) --------------------------------------------
step "Distro detection (informational)"
if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    log "  Detected: ${ID:-unknown} (${PRETTY_NAME:-unknown})"
else
    warn "/etc/os-release not readable -- distro detection skipped."
fi

# --- Plasmoid ----------------------------------------------------------------
step "Plasmoid ($PLASMOID_ID)"
if [ ! -d "$PLASMOID_SRC" ]; then
    die "plasmoid source not found: $PLASMOID_SRC"
fi
ACTION=--install
if [ -d "$PLASMOID_DST" ] || kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -qF "$PLASMOID_ID"; then
    ACTION=--upgrade
fi
log "  kpackagetool6 --type Plasma/Applet $ACTION $PLASMOID_SRC"
if [ "$DRY_RUN" = 0 ]; then
    kpackagetool6 --type Plasma/Applet "$ACTION" "$PLASMOID_SRC"
fi

# --- CLIs ----------------------------------------------------------------
step "CLIs (bin/* -> $BIN_DST)"
for f in bin/*; do
    [ -f "$f" ] || continue
    install_file "$f" "$BIN_DST/$(basename "$f")" 755 0
done

# --- Privileged helpers ----------------------------------------------------
step "Privileged helpers (system/usr-local-sbin/* -> $SBIN_DST, root)"
for f in system/usr-local-sbin/*; do
    [ -f "$f" ] || continue
    # Dereference symlinks (msw-config -> ../../bin/msw-config) so the
    # installed copy under /usr/local/sbin is a real, standalone, root-owned
    # file, not a dangling/relative symlink.
    src=$(readlink -f "$f")
    install_file "$src" "$SBIN_DST/$(basename "$f")" 755 1
done

# --- Optional systemd unit ---------------------------------------------------
step "systemd unit: msw-charge-thresholds.service (opt-in)"
if [ "$WITH_CHARGE_SERVICE" = 1 ]; then
    install_file "system/systemd/msw-charge-thresholds.service" "$SYSTEMD_DST/msw-charge-thresholds.service" 644 1
    log "  [sudo] systemctl daemon-reload"
    [ "$DRY_RUN" = 0 ] && sudo systemctl daemon-reload
    log "  Not enabled automatically. Enable with: sudo systemctl enable --now msw-charge-thresholds.service"
else
    log "  Skipped (pass --with-charge-service to install it)."
fi

# --- Scoped sudoers ----------------------------------------------------------
step "Scoped sudoers (exactly the 4 helper paths)"
if [ "$NO_SUDOERS" = 1 ]; then
    log "  Skipped (--no-sudoers)."
else
    [ -f "$SUDOERS_SRC" ] || die "sudoers source not found: $SUDOERS_SRC"
    REAL_USER=$(id -un)
    # Substitute __USER__ only on the active (non-comment) grant line -- the
    # header comments also mention the literal placeholder token as
    # documentation and must keep reading "__USER__", not the real username.
    SUDOERS_CONTENT=$(awk -v u="$REAL_USER" '
        /^[[:space:]]*#/ { print; next }
        { gsub(/__USER__/, u); print }
    ' "$SUDOERS_SRC")
    log "  Target: $SUDOERS_DST (mode 440, root), for user: $REAL_USER"
    log "  Content:"
    while IFS= read -r line; do log "    $line"; done <<<"$SUDOERS_CONTENT"

    if [ "$DRY_RUN" = 1 ]; then
        log "  (dry-run: would prompt for consent unless --yes, validate with 'visudo -c -f', then install)"
    else
        PROCEED=$ASSUME_YES
        if [ "$ASSUME_YES" = 0 ]; then
            printf 'Install this sudoers file, granting NOPASSWD for exactly the 4 helpers above? [y/N] '
            read -r REPLY || REPLY=""
            case "$REPLY" in
                y|Y|yes|YES) PROCEED=1 ;;
                *) PROCEED=0 ;;
            esac
        fi
        if [ "$PROCEED" = 1 ]; then
            TMP=$(mktemp)
            printf '%s\n' "$SUDOERS_CONTENT" > "$TMP"
            if visudo -c -f "$TMP" >/dev/null; then
                sudo install -D -m 440 "$TMP" "$SUDOERS_DST"
                log "  Installed: $SUDOERS_DST"
            else
                rm -f "$TMP"
                die "generated sudoers content failed 'visudo -c -f' -- NOT installed."
            fi
            rm -f "$TMP"
        else
            log "  Declined -- not installed. The 4 privileged actions will prompt for a password (or fail) without it."
        fi
    fi
fi

# --- Default config -----------------------------------------------------------
step "Default config"
if [ -e "$CONFIG_DST" ]; then
    log "  Exists, left untouched: $CONFIG_DST"
else
    log "  install -D -m 644 config/config.example.json -> $CONFIG_DST"
    [ "$DRY_RUN" = 0 ] && install -D -m 644 config/config.example.json "$CONFIG_DST"
fi

# --- PATH check --------------------------------------------------------------
step "PATH check"
case ":$PATH:" in
    *":$BIN_DST:"*) log "  $BIN_DST is already on PATH." ;;
    *) warn "$BIN_DST is not on PATH -- add it to your shell profile, e.g.: export PATH=\"$BIN_DST:\$PATH\"" ;;
esac

# --- Next steps ----------------------------------------------------------------
step "Next steps"
cat <<EOF
  1. Reload the plasmoid:  kquitapp6 plasmashell && kstart plasmashell  (or log out/in)
  2. Right-click the desktop/panel -> Add Widgets... -> search "Mobile Server Switch"
  3. Edit $CONFIG_DST to enable services / override auto-detection.
EOF
[ "$DRY_RUN" = 1 ] && log "(dry-run: nothing was installed)"
exit 0
