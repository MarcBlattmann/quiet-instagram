#!/usr/bin/env bash
#
# Watch Downloads for a new Instagram apk and rebuild HealthyIG from it.
#
# Designed to be run unattended from cron. It is idempotent and cheap when
# there is nothing to do, so running it hourly is fine - it exits in
# milliseconds unless a genuinely new apk has appeared.
#
#   bash auto_update.sh            # normal cron invocation
#   bash auto_update.sh --force    # rebuild even if this apk was already built
#   bash auto_update.sh --status   # show what it thinks the current state is
#
# What it cannot do: download the apk (APKMirror is Cloudflare-gated and
# forbids automation) or install the result (Android requires a user tap
# unless the device is rooted). Both of those stay manual.

set -euo pipefail

# cron gives a minimal environment - make sure Termux's bin dir is reachable.
export PATH="${PREFIX:-/data/data/com.termux/files/usr}/bin:$PATH"

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
state_file="$repo_dir/.last_built"
lock_dir="$repo_dir/.build.lock"
log_file="$repo_dir/auto_update.log"
downloads="$HOME/storage/downloads"

force=0
status_only=0
for arg in "$@"; do
    case "$arg" in
        --force)  force=1 ;;
        --status) status_only=1 ;;
        *) printf 'Unknown option: %s\n' "$arg" >&2; exit 2 ;;
    esac
done

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

notify() {
    # Termux:API is optional - stay silent rather than fail if it is absent.
    if command -v termux-notification >/dev/null 2>&1; then
        termux-notification --title "HealthyIG" --content "$1" --id healthyig-update >/dev/null 2>&1 || true
    fi
}

###############################################################################
# Identify the newest Instagram apk in Downloads
###############################################################################
# Identity is "basename + byte size". Comparing versions by parsing filenames
# is fragile because APKMirror's naming varies; size catches a genuinely
# different build even if someone renames the file.

find_newest_apk() {
    [ -d "$downloads" ] || return 1
    find -L "$downloads" -maxdepth 2 -type f \
        \( -iname "*instagram*.apk" -o -iname "ig.apk" \) -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | head -1 | cut -d' ' -f2-
}

apk_identity() {
    printf '%s %s' "$(basename "$1")" "$(stat -c%s "$1" 2>/dev/null || echo 0)"
}

###############################################################################
# --status
###############################################################################

if [ "$status_only" -eq 1 ]; then
    printf 'Repo:       %s\n' "$repo_dir"
    printf 'Downloads:  %s\n' "$([ -d "$downloads" ] && echo ok || echo MISSING)"
    if apk="$(find_newest_apk)" && [ -n "$apk" ]; then
        printf 'Newest apk: %s\n' "$(basename "$apk")"
        printf 'Identity:   %s\n' "$(apk_identity "$apk")"
    else
        printf 'Newest apk: none found\n'
    fi
    printf 'Last built: %s\n' "$([ -f "$state_file" ] && cat "$state_file" || echo "never")"
    printf 'Build lock: %s\n' "$([ -d "$lock_dir" ] && echo "HELD (build in progress)" || echo free)"
    printf 'Log:        %s\n' "$log_file"
    exit 0
fi

###############################################################################
# Main
###############################################################################

exec >>"$log_file" 2>&1

apk="$(find_newest_apk || true)"
if [ -z "$apk" ]; then
    log "No Instagram apk in Downloads - nothing to do."
    exit 0
fi

identity="$(apk_identity "$apk")"
last="$([ -f "$state_file" ] && cat "$state_file" || echo "")"

if [ "$identity" = "$last" ] && [ "$force" -eq 0 ]; then
    # Quiet no-op: this is the common case on every cron tick.
    exit 0
fi

log "New apk detected: $(basename "$apk")"

# mkdir is atomic - this is the lock. Prevents a second cron tick from starting
# a parallel build (which would fight over ig_plain and corrupt both).
if ! mkdir "$lock_dir" 2>/dev/null; then
    log "A build is already in progress - skipping this tick."
    exit 0
fi
cleanup() { rmdir "$lock_dir" 2>/dev/null || true; termux-wake-unlock >/dev/null 2>&1 || true; }
trap cleanup EXIT

# Don't chew through the battery: the rebuild pegs every core for hours.
if command -v termux-battery-status >/dev/null 2>&1; then
    plugged="$(termux-battery-status 2>/dev/null | grep -o '"plugged"[^,]*' || true)"
    if [ -n "$plugged" ] && ! printf '%s' "$plugged" | grep -qi 'plugged_'; then
        log "On battery - deferring until the phone is charging."
        notify "New Instagram apk found. Plug in the phone and it will build overnight."
        exit 0
    fi
fi

command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock || true

notify "Building HealthyIG from $(basename "$apk") - this takes a few hours."
log "Starting build ..."

if bash "$repo_dir/build_termux.sh" "$apk"; then
    printf '%s' "$identity" > "$state_file"
    log "Build succeeded."
    notify "HealthyIG is ready in Downloads. Tap to install it."
else
    log "Build FAILED - see the output above. Retry manually with:"
    log "  bash $repo_dir/build_termux.sh --resume"
    notify "HealthyIG build failed. Check auto_update.log."
    exit 1
fi
