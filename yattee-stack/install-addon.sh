#!/usr/bin/env bash
# One-shot installer for the Yattee Server Home Assistant add-on.
#
# Run this in the terminal of the "Advanced SSH & Web Terminal" add-on on the
# Home Assistant Green. It fetches the add-on files into /addons/yattee-server/
# so you do not have to move them over Samba by hand.
#
#   curl -fsSL https://raw.githubusercontent.com/bezanisniko-del/YouTube-Premium-/claude/youtube-adblock-app-plan-ugp00x/yattee-stack/install-addon.sh | bash
#
# Or paste the file in and run it. It only writes to /addons/yattee-server/ and
# never touches your Home Assistant configuration.
#
# After it finishes: Settings -> Add-ons -> Add-on Store -> (three dots) ->
# Check for updates. "Yattee Server" appears under Local add-ons.

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/bezanisniko-del/YouTube-Premium-"
BRANCH="claude/youtube-adblock-app-plan-ugp00x"
SRC="${REPO_RAW}/${BRANCH}/yattee-stack/homeassistant-addon"
DEST="${DEST:-/addons/yattee-server}"
FILES="config.yaml Dockerfile run.sh README.md"

log()   { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[33m warn\033[0m %s\n' "$*"; }
fatal() { printf '\033[31mfatal\033[0m %s\n' "$*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || fatal "curl not found — run this from the Advanced SSH & Web Terminal add-on."

# /addons is the local add-on share. On Home Assistant 2026.07+ the internal
# path moved to apps/local, but Supervisor keeps /addons linked, so this stays
# correct on both.
if [ ! -d "$(dirname "$DEST")" ]; then
    fatal "$(dirname "$DEST") does not exist. Are you inside the SSH add-on with Protection mode off?"
fi

log "installing into ${DEST}"
mkdir -p "$DEST"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

for f in $FILES; do
    if ! curl -fsSL --max-time 45 -o "${TMP}/${f}" "${SRC}/${f}"; then
        fatal "could not download ${f} from ${SRC}. Check the Green's internet access."
    fi
    # Guard against a 404 page or an HTML error being saved as a config file.
    if [ ! -s "${TMP}/${f}" ]; then
        fatal "${f} downloaded empty"
    fi
    printf '    fetched %-12s %6s bytes\n' "$f" "$(wc -c < "${TMP}/${f}" | tr -d ' ')"
done

# Sanity-check before overwriting anything that already exists.
grep -q '^slug: yattee_server' "${TMP}/config.yaml" \
    || fatal "config.yaml does not look right (no matching slug) — refusing to install"
grep -q '^FROM yattee/yattee-server' "${TMP}/Dockerfile" \
    || fatal "Dockerfile does not look right — refusing to install"

if [ -f "${DEST}/config.yaml" ]; then
    warn "${DEST} already exists — overwriting the add-on files"
    warn "your configured options are stored by Supervisor, not here, so they survive"
fi

for f in $FILES; do
    cp "${TMP}/${f}" "${DEST}/${f}"
done
chmod +x "${DEST}/run.sh"

log "installed:"
ls -la "$DEST"

cat <<'EOF'

Next:

  1. Settings -> Add-ons -> Add-on Store -> (three dots) -> Check for updates
  2. "Yattee Server" appears under Local add-ons. Install it.
     First build pulls a ~400 MB image; on the Green this takes a few minutes.
  3. Configuration tab:
       admin_username         admin
       admin_password         generate one:  openssl rand -base64 24
       invidious_instance_url leave EMPTY
       ytdlp_version          latest
  4. Info tab: enable "Start on boot" and "Watchdog", then Start.
  5. Check the Log tab for:  starting on 0.0.0.0:8085
  6. Verify before touching your phone:
       export YS_PASS='the password you set'
       curl -fsSL https://raw.githubusercontent.com/bezanisniko-del/YouTube-Premium-/claude/youtube-adblock-app-plan-ugp00x/yattee-stack/verify.sh -o /tmp/verify.sh
       bash /tmp/verify.sh --url http://homeassistant.local:8085 --user admin
     Expect 7/7.

EOF
