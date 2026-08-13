#!/bin/sh
# Entrypoint for the Yattee Server Home Assistant add-on.
#
# Runs as PID 1 (config.yaml sets init: false). Reads add-on options from
# /data/options.json, exports them as the environment variables yattee-server
# expects (config.py), optionally refreshes yt-dlp, then execs uvicorn.
#
# POSIX sh: the upstream image is python:3.12-slim, which has no bash and no
# bashio. Python 3.12 is guaranteed present, so it does the JSON parsing.

set -eu

OPTIONS_FILE=/data/options.json

log() { printf '[yattee-server] %s\n' "$*"; }
fatal() { printf '[yattee-server] FATAL: %s\n' "$*" >&2; exit 1; }

[ -f "$OPTIONS_FILE" ] || fatal "$OPTIONS_FILE not found — is this running as an HA add-on?"

# Emit `key=value` per line. Never echo the password: it is read straight into
# the environment below without passing through the log.
opt() {
    python3 -c '
import json, sys
with open("/data/options.json") as fh:
    print(json.load(fh).get(sys.argv[1], "") or "")
' "$1"
}

ADMIN_USERNAME=$(opt admin_username)
ADMIN_PASSWORD=$(opt admin_password)
INVIDIOUS_INSTANCE_URL=$(opt invidious_instance_url)
YTDLP_VERSION=$(opt ytdlp_version)
LOG_LEVEL=$(opt log_level)

[ -n "$ADMIN_USERNAME" ] || fatal "admin_username is empty — set it in the add-on Configuration tab"
[ -n "$ADMIN_PASSWORD" ] || fatal "admin_password is empty — set it in the add-on Configuration tab"

# env_provisioning.py:28-45 creates or updates this admin on every start, so a
# password change here takes effect on restart.
export ADMIN_USERNAME ADMIN_PASSWORD

# env_provisioning.py:48-59 only acts when this is non-empty; unset means the
# Invidious proxy stays off (see DECISIONS.md D4).
if [ -n "$INVIDIOUS_INSTANCE_URL" ]; then
    export INVIDIOUS_INSTANCE_URL
    log "backing Invidious instance: $INVIDIOUS_INSTANCE_URL"
else
    log "no backing Invidious instance (trending, popular and comments will be empty)"
fi

# Persistent state lives on the add-on's /data volume, which HA backs up.
export DATA_DIR="${DATA_DIR:-/data/server}"
export DOWNLOAD_DIR="${DOWNLOAD_DIR:-/tmp/yattee-downloads}"
mkdir -p "$DATA_DIR" "$DOWNLOAD_DIR"

# --- yt-dlp currency (DECISIONS.md D3) -------------------------------------
# The pinned image freezes yt-dlp at its build date. YouTube breaks extraction
# on a weeks-to-months cadence and the fix is almost always a newer yt-dlp, so
# refresh it at start. A failure here is non-fatal: the image's own yt-dlp is
# still there, and refusing to boot over a transient network error would be
# worse than running slightly stale.
case "$YTDLP_VERSION" in
    skip|"")
        log "yt-dlp: using image version (upgrade skipped)"
        ;;
    latest)
        log "yt-dlp: upgrading to latest"
        pip install --no-cache-dir --upgrade yt-dlp \
            || log "WARNING: yt-dlp upgrade failed, continuing with image version"
        ;;
    *)
        log "yt-dlp: pinning to $YTDLP_VERSION"
        pip install --no-cache-dir "yt-dlp==$YTDLP_VERSION" \
            || log "WARNING: yt-dlp pin to $YTDLP_VERSION failed, continuing with image version"
        ;;
esac
log "yt-dlp in use: $(yt-dlp --version 2>/dev/null || echo unknown)"

# --- launch ----------------------------------------------------------------
# uvicorn is invoked directly rather than via the image's CMD because the PORT
# env var does nothing there: the image CMD hardcodes --port 8085
# (Dockerfile, and config.py:9 defaults PORT to 8080 regardless). See
# DECISIONS.md "Docs-vs-code discrepancies", item 4.
log "starting on 0.0.0.0:8085 (log level ${LOG_LEVEL:-info})"
exec uvicorn server:app \
    --host 0.0.0.0 \
    --port 8085 \
    --log-level "${LOG_LEVEL:-info}"
