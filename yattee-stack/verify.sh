#!/usr/bin/env bash
# Regression check for the Yattee Server stack.
#
# Run this after every yt-dlp bump, after every add-on restart you care about,
# and first whenever playback breaks on the phone.
#
# Usage:
#   ./verify.sh                                  # uses env vars / defaults
#   YS_URL=http://green:8085 YS_USER=admin YS_PASS=... ./verify.sh
#   ./verify.sh --url http://green:8085 --user admin --pass secret
#
# Exit status: 0 if every check passed, 1 otherwise.
#
# Dependencies: bash 4+, curl, python3. All present on the HA "Advanced SSH &
# Web Terminal" add-on and on any normal Linux host.

set -uo pipefail

YS_URL="${YS_URL:-http://127.0.0.1:8085}"
YS_USER="${YS_USER:-admin}"
YS_PASS="${YS_PASS:-}"
# "Never Gonna Give You Up" — the same ID Yattee itself probes with, so a pass
# here means the app's own instance detection will also pass.
VIDEO_ID="${VIDEO_ID:-dQw4w9WgXcQ}"
LATENCY_RUNS="${LATENCY_RUNS:-5}"

while [ $# -gt 0 ]; do
    case "$1" in
        --url)   YS_URL="$2";  shift 2 ;;
        --user)  YS_USER="$2"; shift 2 ;;
        --pass)  YS_PASS="$2"; shift 2 ;;
        --video) VIDEO_ID="$2"; shift 2 ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

YS_URL="${YS_URL%/}"

if [ -z "$YS_PASS" ]; then
    echo "YS_PASS is empty. Export it or pass --pass; do not inline the password" >&2
    echo "in a shell that records history." >&2
    exit 2
fi

PASS=0
FAIL=0
RESULTS=()

green()  { printf '\033[32m%s\033[0m' "$1"; }
red()    { printf '\033[31m%s\033[0m' "$1"; }

record() { # name, ok(0/1), detail
    local name="$1" ok="$2" detail="$3"
    if [ "$ok" -eq 0 ]; then
        PASS=$((PASS + 1))
        printf '  [%s] %-34s %s\n' "$(green PASS)" "$name" "$detail"
        RESULTS+=("PASS $name")
    else
        FAIL=$((FAIL + 1))
        printf '  [%s] %-34s %s\n' "$(red FAIL)" "$name" "$detail"
        RESULTS+=("FAIL $name")
    fi
}

# curl wrapper. Basic Auth via --user; -sS keeps it quiet but still reports
# hard errors. Writes body to $BODY and echoes the status code.
BODY=$(mktemp)
trap 'rm -f "$BODY"' EXIT

req() { # path [extra curl args...]
    local path="$1"; shift
    curl -sS --max-time 45 -u "${YS_USER}:${YS_PASS}" \
         -o "$BODY" -w '%{http_code}' "${YS_URL}${path}" "$@" 2>/dev/null
}

# Reads $BODY as JSON and prints the result of a python expression on `d`.
# Prints nothing and returns 1 if the body is not JSON.
jq_py() { python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
try:
    print(eval(sys.argv[2], {"d": d, "len": len, "str": str}))
except Exception:
    sys.exit(1)
' "$BODY" "$1" 2>/dev/null; }

is_2xx() { [ "$1" -ge 200 ] && [ "$1" -lt 300 ]; }

echo
echo "Yattee Server verification — ${YS_URL}"
echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ')  video=${VIDEO_ID}"
echo

# --- 1. health -------------------------------------------------------------
# /api/v1/stats does not exist on Yattee Server and Yattee never calls one.
# /health is public; /info is the authenticated equivalent and proves the
# credentials work, so both are checked here.
hcode=$(req /health)
hok=$([ "$(jq_py 'd.get("status")')" = "ok" ] && is_2xx "$hcode" && echo yes || echo no)

icode=$(req /info)
ver=$(jq_py 'd.get("version","?")')
ytdlp=$(jq_py 'd.get("dependencies",{}).get("yt-dlp","?")')
# basic_auth.py:170-175 returns {"name": "yattee-server"} with no dependencies
# key when the Authorization header is missing or wrong, so the presence of
# that key is what proves the credentials were accepted.
iok=$([ "$(jq_py 'str("dependencies" in d)')" = "True" ] && is_2xx "$icode" && echo yes || echo no)

if [ "$hok" = yes ] && [ "$iok" = yes ]; then
    record "1 health + authenticated info" 0 "server=${ver} yt-dlp=${ytdlp}"
elif [ "$hok" = yes ]; then
    record "1 health + authenticated info" 1 "/health ok but /info HTTP ${icode} — credentials rejected"
else
    record "1 health + authenticated info" 1 "/health HTTP ${hcode}"
fi

# --- 2. video metadata extraction -------------------------------------------
code=$(req "/api/v1/videos/${VIDEO_ID}")
if is_2xx "$code"; then
    author=$(jq_py 'd.get("author","")')
    nfmt=$(jq_py 'len(d.get("formatStreams",[])) + len(d.get("adaptiveFormats",[]))')
    method=$(jq_py 'd.get("extractionMethod","?")')
    if [ "${nfmt:-0}" -gt 0 ]; then
        record "2 video metadata" 0 "author='${author}' formats=${nfmt} via=${method}"
    else
        record "2 video metadata" 1 "200 but zero stream formats — extraction is broken"
    fi
    # Yattee's own instance detection asserts author == "Rick Astley"
    # (AccountValidator at 1.5.1; 2.0 detects via /info). Surfaced as a warning
    # rather than a failure so a different --video does not trip it.
    if [ "$VIDEO_ID" = "dQw4w9WgXcQ" ] && [ "$author" != "Rick Astley" ]; then
        echo "        note: author is '${author}', expected 'Rick Astley'"
    fi
else
    record "2 video metadata" 1 "HTTP $code"
fi

# --- 3. search with filters -------------------------------------------------
# Server reads `sort`, not Invidious's `sort_by` (routers/search.py:56).
code=$(req "/api/v1/search?q=rick+astley&type=video&sort=relevance&date=year&duration=short&page=1")
if is_2xx "$code"; then
    n=$(jq_py 'len(d) if isinstance(d, list) else -1')
    if [ "${n:-0}" -gt 0 ]; then
        record "3 search with filters" 0 "${n} results"
    else
        record "3 search with filters" 1 "200 but empty result array"
    fi
else
    record "3 search with filters" 1 "HTTP $code"
fi

# --- 4. channel listing -----------------------------------------------------
# Rick Astley's channel. Resolved from the video response so this keeps working
# if the channel ID ever changes.
code=$(req "/api/v1/videos/${VIDEO_ID}")
CHANNEL_ID=$(jq_py 'd.get("authorId","")')
if [ -z "${CHANNEL_ID:-}" ]; then
    record "4 channel listing" 1 "could not resolve a channel ID from the video response"
else
    code=$(req "/api/v1/channels/${CHANNEL_ID}/videos")
    if is_2xx "$code"; then
        n=$(jq_py 'len(d.get("videos",[]))')
        if [ "${n:-0}" -gt 0 ]; then
            record "4 channel listing" 0 "${CHANNEL_ID} -> ${n} videos"
        else
            record "4 channel listing" 1 "200 but zero videos for ${CHANNEL_ID}"
        fi
    else
        record "4 channel listing" 1 "HTTP $code for ${CHANNEL_ID}"
    fi
fi

# --- 5. proxied stream ------------------------------------------------------
# Force proxying on so the relay path is exercised even when the site's
# proxy_streaming flag is off (which is the recommended steady state — see
# DECISIONS.md D2). This proves the relay still works as a fallback.
code=$(req "/api/v1/videos/${VIDEO_ID}?proxy=true&proxy_mode=relay")
STREAM_URL=""
if is_2xx "$code"; then
    STREAM_URL=$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
for key in ("formatStreams", "adaptiveFormats"):
    for f in d.get(key, []):
        u = f.get("url", "")
        if "/proxy/" in u:
            print(u)
            sys.exit(0)
' "$BODY" 2>/dev/null)
fi

if [ -z "$STREAM_URL" ]; then
    record "5 proxied stream URL" 1 "no /proxy/ URL in the response (HTTP $code)"
else
    # HMAC token must survive intact: /proxy/relay is public to Basic Auth
    # (basic_auth.py:25-35) and authorises on `sig`+`exp` instead.
    has_sig=$(printf '%s' "$STREAM_URL" | grep -c 'sig=' || true)
    hdrs=$(curl -sS --max-time 45 -r 0-1048575 -o /dev/null \
                -D - "$STREAM_URL" 2>/dev/null)
    scode=$(printf '%s' "$hdrs" | awk 'toupper($1) ~ /^HTTP/ {print $2}' | tail -1)
    clen=$(printf '%s' "$hdrs" | awk 'BEGIN{IGNORECASE=1} /^content-length:/ {gsub(/\r/,""); print $2}' | tail -1)
    clen=${clen:-0}

    if [ "$has_sig" -eq 0 ]; then
        record "5 proxied stream URL" 1 "URL has no sig= — HMAC token was stripped"
    elif { [ "${scode:-0}" = "200" ] || [ "${scode:-0}" = "206" ]; } && [ "$clen" -gt 100000 ]; then
        record "5 proxied stream URL" 0 "HTTP ${scode} content-length=${clen} sig intact"
    else
        record "5 proxied stream URL" 1 "HTTP ${scode:-?} content-length=${clen}"
    fi
fi

# --- 6. captions ------------------------------------------------------------
code=$(req "/api/v1/captions/${VIDEO_ID}")
if is_2xx "$code"; then
    n=$(jq_py 'len(d.get("captions",[])) if isinstance(d, dict) else len(d)')
    if [ "${n:-0}" -gt 0 ]; then
        record "6 captions" 0 "${n} caption tracks"
    else
        # Without a backing Invidious instance this can legitimately be empty
        # for some videos. Reported as a failure because dQw4w9WgXcQ does have
        # captions; if you switched --video, judge accordingly.
        record "6 captions" 1 "200 but zero caption tracks"
    fi
else
    record "6 captions" 1 "HTTP $code"
fi

# --- 7. cold-start latency, p50 over N runs ---------------------------------
# Measures checks 2 and 5. Cache TTLs (cache_video_ttl, default 3600s) mean
# runs 2..N are warm — that is deliberate: run 1 shows the cold cost, the
# median shows what the phone actually feels on a re-open.
p50() { python3 -c '
import sys
xs = sorted(float(x) for x in sys.argv[1:] if x)
if not xs:
    print("n/a"); sys.exit()
n = len(xs)
print(f"{(xs[n//2] if n % 2 else (xs[n//2 - 1] + xs[n//2]) / 2):.3f}s")
' "$@"; }

meta_times=()
meta_ok=0
for _ in $(seq 1 "$LATENCY_RUNS"); do
    out=$(curl -sS --max-time 45 -u "${YS_USER}:${YS_PASS}" -o /dev/null \
               -w '%{time_total} %{http_code}' "${YS_URL}/api/v1/videos/${VIDEO_ID}" 2>/dev/null)
    t=${out%% *}; c=${out##* }
    if is_2xx "${c:-0}"; then
        meta_times+=("$t")
        meta_ok=$((meta_ok + 1))
    fi
done
meta_p50=$(p50 "${meta_times[@]+"${meta_times[@]}"}")

stream_p50="n/a"
if [ -n "$STREAM_URL" ]; then
    stream_times=()
    for _ in $(seq 1 "$LATENCY_RUNS"); do
        out=$(curl -sS --max-time 45 -r 0-262143 -o /dev/null \
                   -w '%{time_total} %{http_code}' "$STREAM_URL" 2>/dev/null)
        t=${out%% *}; c=${out##* }
        if [ "${c:-0}" = "200" ] || [ "${c:-0}" = "206" ]; then
            stream_times+=("$t")
        fi
    done
    stream_p50=$(p50 "${stream_times[@]+"${stream_times[@]}"}")
fi

# Timings from failed requests are meaningless, so this check only passes when
# every run actually succeeded.
if [ "$meta_ok" -eq "$LATENCY_RUNS" ] && [ "$meta_p50" != "n/a" ]; then
    record "7 latency p50 (n=${LATENCY_RUNS})" 0 "metadata=${meta_p50}  stream-first-256KiB=${stream_p50}"
else
    record "7 latency p50 (n=${LATENCY_RUNS})" 1 "only ${meta_ok}/${LATENCY_RUNS} metadata requests succeeded"
fi

# --- summary ----------------------------------------------------------------
TOTAL=$((PASS + FAIL))
echo
if [ "$FAIL" -eq 0 ]; then
    echo "$(green "SUMMARY: ${PASS}/${TOTAL} passed") — ${YS_URL} healthy"
    exit 0
else
    echo "$(red "SUMMARY: ${PASS}/${TOTAL} passed, ${FAIL} failed") — ${YS_URL}"
    printf '%s\n' "${RESULTS[@]}" | grep '^FAIL' | sed 's/^/  /'
    echo
    echo "Next steps: DECISIONS.md -> 'Known failure modes'."
    exit 1
fi
