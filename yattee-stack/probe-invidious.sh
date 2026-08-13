#!/usr/bin/env bash
# Health-probe the public Invidious instances before adopting one as
# INVIDIOUS_INSTANCE_URL / the add-on's invidious_instance_url option.
#
# Run this ON THE HOME ASSISTANT GREEN, not from a laptop: what matters is
# whether the machine that will actually call these instances can reach them,
# from its address, without hitting an anti-bot challenge.
#
# The recommendation in DECISIONS.md D4 is to leave the setting empty. Use this
# only if you decide you want trending, popular or comments.
#
# Usage:
#   ./probe-invidious.sh
#   ./probe-invidious.sh https://some.other.instance
#
# An instance is usable only if BOTH columns say ok AND author is "Rick Astley".
# A 403, a Cloudflare interstitial, or an HTML body means an anti-bot layer is
# in the way — the API cannot be driven server-to-server.

set -uo pipefail

# github.com/iv-org/documentation/docs/instances.md, read 2026-07-28.
# Re-read that file before trusting this list; it changes.
DEFAULT_INSTANCES=(
    https://inv.nadeko.net            # CL — listed as "CAPTCHA: Go-away"
    https://invidious.nerdvpn.de      # UA
    https://yt.chocolatemoo53.com     # US
    https://invidious.tiekoetter.com  # DE
    https://invidious.f5.si           # JP
    https://inv.zoomerville.com       # US
)

if [ $# -gt 0 ]; then
    INSTANCES=("$@")
else
    INSTANCES=("${DEFAULT_INSTANCES[@]}")
fi

VIDEO_ID=dQw4w9WgXcQ
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

printf '%-34s %-8s %-8s %-9s %s\n' INSTANCE STATS VIDEOS TIME AUTHOR
printf '%-34s %-8s %-8s %-9s %s\n' "$(printf '%.34s' '----------------------------------')" -------- -------- --------- ------

for base in "${INSTANCES[@]}"; do
    base="${base%/}"
    host=${base#https://}

    # curl exits non-zero on a connection failure but -w still prints, so the
    # output is taken as-is and only substituted when it comes back empty.
    scode=$(curl -sS --max-time 15 -o /dev/null -w '%{http_code}' \
                 "${base}/api/v1/stats" 2>/dev/null)
    scode=${scode:-000}

    vout=$(curl -sS --max-time 25 -o "$TMP" -w '%{http_code} %{time_total}' \
                "${base}/api/v1/videos/${VIDEO_ID}" 2>/dev/null)
    vout=${vout:-000 0}
    vcode=${vout%% *}
    vtime=${vout##* }

    author=$(python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("non-JSON (anti-bot page?)"); sys.exit()
print(d.get("author") or d.get("error") or "?")
' "$TMP" 2>/dev/null || echo "?")

    fmt() { case "$1" in 2??) echo "ok($1)" ;; 000) echo "unreach" ;; *) echo "$1" ;; esac; }

    printf '%-34s %-8s %-8s %-9s %s\n' \
        "$host" "$(fmt "$scode")" "$(fmt "$vcode")" "${vtime}s" "$author"
done

cat <<'EOF'

Adopt an instance only if VIDEOS is ok(200) and AUTHOR is exactly "Rick Astley".
Then set it in the add-on Configuration tab (invidious_instance_url) and restart.
Re-run ./verify.sh afterwards — a flaky backing instance degrades the whole
server, since routers/search.py falls through Invidious on its way to yt-dlp.
EOF
