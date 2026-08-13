# DECISIONS

Decision record for the self-hosted YouTube stack. Every external fact carries the
date it was checked. Anything older than ~6 months should be re-verified before
you rely on it.

**Verification date for everything below: 2026-07-28**, unless stated otherwise.

---

## D0 — Phase 0 go/no-go on the App Store client

### Verdict: **NO-GO for Yattee 1.5.1 (App Store).** Target Yattee 2.0 instead.

Yattee Server is a Yattee **2.x** backend. It was never a 1.x feature. The 1.x
client can be pointed at it as a generic Invidious instance and will play video,
but the pieces that make the source usable day to day — authentication,
subscriptions, the feed — are absent or wired to endpoints the server does not
serve.

**Primary evidence** (code, not docs):

| Claim | Where |
|---|---|
| `InstanceType.yatteeServer` exists only in 2.0 | `yattee@main:Yattee/Models/Instance.swift:15` — no equivalent in `yattee@v1.5.1` |
| 2.0 has a dedicated Yattee Server API client | `yattee@main:Yattee/Services/API/YatteeServerAPI.swift` — no such file at v1.5.1 |
| 2.0 has first-class HTTP Basic Auth support | `yattee@main:Yattee/Services/Credentials/BasicAuthCredentialsManager.swift`, `Yattee/Services/API/InstanceDetector.swift` (`DetectionError.basicAuthRequired` / `.basicAuthInvalid`) — neither exists at v1.5.1 |
| 1.5.1's only auth path is Invidious `POST /login` → `SID` cookie | `yattee@v1.5.1:Model/Applications/InvidiousAPI.swift:185-215`, `Model/Accounts/AccountValidator.swift:158-188` |
| Yattee Server has no Invidious-style `/login`; auth is HTTP Basic, enforced globally | `yattee-server@1.0.7:basic_auth.py:154-243`. Its `POST /api/login` (`routers/admin/pages.py:136`) is a JSON admin-panel probe, not the form-encoded cookie flow 1.5.1 drives. |
| Upstream states the pairing | `yattee@main:README.md` — "Yattee 2 … pairs with the new Yattee Server" |

v1.5.1 is tag `9c51f24`, committed **2024-01-13** — roughly two years before
Yattee Server 1.0.0 was first published (Docker Hub tag `1.0.0`, pushed
**2026-02-08**). The client predates the server it would be talking to.

### Coverage matrix — endpoints Yattee 1.5.1 calls vs. what the server implements

Client call sites: `yattee@v1.5.1:Model/Applications/InvidiousAPI.swift`,
`Model/Accounts/AccountValidator.swift`.
Server routes: `yattee-server@1.0.7:routers/*.py`, `invidious_proxy.py`,
registered in `server.py:124-155`.

| Endpoint | Called by 1.5.1 | Served by 1.0.7 | Severity |
|---|---|---|---|
| `GET /api/v1/videos/{id}` | yes (`InvidiousAPI.swift:303`) | yes (`routers/videos.py:60`) | ok |
| `GET /api/v1/videos/dQw4w9WgXcQ` (instance validation, asserts `author == "Rick Astley"`) | yes (`AccountValidator.swift:55,109`) | yes | ok — but see D1 |
| `GET /api/v1/search` | yes (`:391`) | yes (`routers/search.py:53`) | **degraded** — client sends `sort_by`, server reads `sort` (`search.py:56`). Sort filter silently ignored. Client also sends `type=all`; server accepts it. |
| `GET /api/v1/search/suggestions` | yes (`:412`) | yes (`routers/search.py:108`) | **degraded** — server returns a bare JSON array (`response_model=List[str]`); client reads `json["suggestions"]` (`:83`) and gets nothing. Suggestions silently empty. |
| `GET /api/v1/trending` | yes (`:240`) | yes (`routers/search.py:129`) | ok (needs backing Invidious — see D4) |
| `GET /api/v1/popular` | yes (`:236`) | yes (`routers/search.py:154`) | ok (needs backing Invidious) |
| `GET /api/v1/channels/{id}` | yes (`:278`) | yes (`routers/channels.py:83`) | ok |
| `GET /api/v1/channels/{id}/{videos,playlists,shorts,streams}` | yes (`:281`) | yes (`channels.py:210,373,416,464`) | ok |
| `GET /api/v1/channels/{id}/latest` | yes (`:299`) | **no** | **blocker** for the channel-videos path that uses it |
| `GET /api/v1/channels/{id}/{channels,releases,podcasts}` | yes (`:126`) | **no** | cosmetic — empty tabs |
| `GET /api/v1/playlists/{id}` | yes (`:387`) | yes (`routers/playlists.py:18`) | ok |
| `GET /api/v1/comments/{id}` | yes (`:417`) | yes (`routers/comments.py:44`) | ok (needs backing Invidious) |
| `GET/POST/DELETE /api/v1/auth/subscriptions` | yes (`:259-273`) | **no** | **blocker** — no subscriptions |
| `GET /api/v1/auth/feed` | yes (`:250`) | **no** — server exposes `POST /api/v1/feed` with a client-supplied channel list (`routers/subscriptions.py:108`), a different contract 1.5.1 cannot drive | **blocker** — no feed |
| `GET/POST/PATCH/DELETE /api/v1/auth/playlists[/…]` | yes (`:311-320`) | **no** | **blocker** — no user playlists |
| `POST /login` (form-encoded, expects `Set-Cookie: SID=`) | yes (`:186`) | **no** | **blocker** — cannot authenticate |
| `GET /feed/subscriptions` | yes (`:246`) | **no** | degraded |

Net: 6 blockers. Video playback and search survive; the app's whole
subscription/feed/playlist half does not.

### Known-issue search

Checked **2026-07-28**: `github.com/yattee/yattee-server/issues` lists 6 issues
total (#1–#7, one deleted), newest #7 "Add a possibility to force yt-dlp to use
IPv6" opened 2026-07-19. **None** mention Yattee 1.x, 1.5, the App Store build,
Basic Auth, or client compatibility. Nobody is reporting 1.x-against-server
breakage because nobody is attempting the pairing.

### Consequence: client is Yattee 2.0 (TestFlight)

- TestFlight: <https://yattee.stream/beta2>
- Current beta: **2.0.0 build 268**, published **2026-07-27**, `minOSVersion 18.0`
  (`yattee@main:altstore-source.json`). Your iPhone on iOS 18.6+ qualifies.
- 2.0 is **iOS-only beta** at this point; macOS and tvOS builds are not out.

**Build-expiry implication.** A TestFlight build stops launching 90 days after
the developer uploads it. That is the worst case, not the cadence: the beta has
shipped builds 250 → 264 → 266 → 268 between 2026-02-09 and 2026-07-27, and
TestFlight auto-updates in the background. In practice the app refreshes itself
every few weeks and you never touch it. The failure mode to know: if upstream
goes quiet for three months, the app refuses to open until a new build lands.
This is **not** the 7-day sideloading treadmill — that was ruled out of scope,
and this does not reintroduce it.

**Do not use the AltStore source** (`altstore-source.json`) as the install path.
It delivers the same IPA but re-signs on a free Apple ID, which *is* the 7-day
treadmill.

---

## D1 — Basic Auth and instance detection

Yattee Server enforces HTTP Basic Auth on every path once a user exists
(`basic_auth.py:154-160`). Exceptions, from `PUBLIC_PATHS` / `MINIMAL_INFO_PATHS`
(`basic_auth.py:25-40`):

- `/health`, `/setup`, `/api/setup`, `/static/`, `/favicon.ico` — fully public.
- `/proxy/`, `/api/v1/thumbnails/`, `/api/v1/captions/` — no Basic Auth; they
  validate an HMAC `token` query parameter at the endpoint instead. This is what
  lets the server hand stream URLs to `AVPlayer`, which cannot carry credentials.
- `/info` — returns `{"name": "yattee-server"}` unauthenticated, full payload
  when authenticated. This is the instance-detection hook.

Yattee 2.0 handles the 401 explicitly (`InstanceDetector.swift`,
`DetectionError.basicAuthRequired`) and prompts for credentials. Enter the URL
**without** credentials embedded and let the app ask.

---

## D2 — Host: Home Assistant Green, as a local add-on

The original spec assumed a Windows Docker host. Rejected: that machine is not
always on, and the whole point is that the phone can play a video at any hour.

**Home Assistant Green** (Rockchip RK3566, 4× Cortex-A55 @ 1.8 GHz, 4 GB LPDDR4X,
32 GB eMMC, gigabit ethernet, ~1.7 W idle — <https://www.home-assistant.io/green/>)
is always on and is the right host. Feasibility:

- `yattee/yattee-server:1.0.7` publishes a **linux/arm64** image (Docker Hub,
  checked 2026-07-28, 403 MB). aarch64 is covered.
- The image's `deno` install (`Dockerfile:8-12`, via `deno.land/install.sh`)
  supports aarch64.
- The server does **not** transcode. yt-dlp extracts, ffmpeg is present but idle
  on the normal playback path. A fanless A55 is adequate.

**Delivery mechanism: a Home Assistant local add-on, not `docker compose`.**
Home Assistant OS does not give you a general-purpose Docker host. Running
unmanaged containers next to Supervisor marks the system unsupported. A local
add-on is a Supervisor-managed container — the supported path, and it gets
HA-native backups, logs, and restart control for free.

`docker-compose.yml` is still committed as a portable fallback for the day this
moves to a real Linux box. It is not the HA Green path.

### Two constraints the hardware imposes

1. **eMMC wear.** `proxy_mode=download` (`/proxy/fast/`) writes video to disk.
   On 32 GB of soldered eMMC that is a wear problem with no repair path. The
   add-on maps `/downloads` to **tmpfs**, so a stray download-mode request costs
   RAM, not flash life.
2. **Keep the Green out of the byte path.** By default the server rewrites stream
   URLs to relay through itself: `routers/videos.py:99-110` falls back to the
   per-site `proxy_streaming` flag, which defaults to `True`, and `proxy_mode`
   defaults to `relay`. Relaying 4K (20–45 Mbps) through Python on an A55 is the
   one way to make this hardware struggle.

   Yattee 2.0's normal fetch sends no `proxy` parameter
   (`YatteeServerAPI.swift:118,247`) and so inherits that default. It only forces
   proxying as an explicit fallback (`:272-285`, `?proxy=true&proxy_mode=relay`).

   **So: set the YouTube site's `proxy_streaming` to off in the admin panel.**
   The phone then pulls bytes straight from googlevideo, the Green only does
   metadata extraction, and the app's relay fallback still works when a direct
   URL is refused. See `IPHONE-SETUP.md` step 9.

---

## D3 — yt-dlp drift: pinned image + upgrade on start

`yattee/yattee-server:1.0.7` was pushed **2026-07-06** and pins
`yt-dlp>=2026.07.04` (`requirements.txt`). The image tag is only bumped when
upstream cuts a release, so a strictly pinned tag freezes yt-dlp at the build
date — already ~3 weeks stale today, and YouTube breakage almost always needs a
*newer* yt-dlp than the image ships.

Decision: **pin the image by digest, and upgrade yt-dlp at container start.**
`homeassistant-addon/run.sh` pip-installs yt-dlp on boot, controlled by the
`ytdlp_version` add-on option:

- `latest` (default) — newest release each start.
- a pinned version like `2026.07.04` — after a bad release, pin the last good one.
- `skip` — use whatever the image ships, no network call at start.

Recovery from a yt-dlp break is then "restart the add-on", and it survives
container recreation, which an interactive `pip install` would not.

Cost, stated plainly: with `latest`, a restart can pull in a yt-dlp regression.
That is what `verify.sh` and the nightly check in `maintenance/` are for — and
why `ytdlp_version` accepts an explicit pin.

---

## D4 — Backing Invidious instance: **leave unset**

`INVIDIOUS_INSTANCE_URL` is optional. Without it the server still serves video,
search, and channels via InnerTube + yt-dlp; `routers/search.py:66-101` shows the
three-tier fallback with Invidious only in the middle.

What you lose with it unset: trending, popular, comments, and the Invidious
fallbacks for captions, thumbnails, and channel avatars. Search *suggestions*
try InnerTube first (`search.py:108-127`) and mostly survive.

Recommendation: **leave it unset**, and add an instance later only if you find
you miss trending or comments.

Justification:

1. The Invidious maintainers say so themselves. The official list
   (`iv-org/documentation/docs/instances.md`, read 2026-07-28) carries: *"The
   list of public instances is short due to the recent YouTube issues. If you
   can, please host Invidious at home instead of using a public instance."*
2. Only six clearnet instances are listed at all: `inv.nadeko.net` 🇨🇱,
   `invidious.nerdvpn.de` 🇺🇦, `yt.chocolatemoo53.com` 🇺🇸,
   `invidious.tiekoetter.com` 🇩🇪, `invidious.f5.si` 🇯🇵, `inv.zoomerville.com` 🇺🇸.
3. `inv.nadeko.net` is annotated **"CAPTCHA: Go-away"** — an interactive
   anti-bot challenge, which a server-to-server API caller cannot satisfy.
   Rule 14 of the listing requirements now *mandates* such measures for all
   public instances, so expect this class of failure broadly.
4. Pointing at a third party puts your viewing on someone else's box for no gain
   on the features you actually asked for.

**Honest limitation:** I could not health-check those six from the environment
this was written in — outbound CONNECT to them was refused by network policy
(403), so every probe returned `000`. That is my sandbox, **not** evidence the
instances are down. `probe-invidious.sh` in this directory runs the check
properly from the Green. Re-verify before adopting any instance.

If you do adopt one, and it resolves to a private address, you will also need
`SSRF_EXTRA_ALLOWED_CIDRS` (`config.py:61-70`). For a public HTTPS instance you
do not.

---

## D5 — Network: Tailscale only

The server is reachable on the tailnet and nowhere else. No published port on
the router, no public DNS record, no reverse proxy. Basic Auth stays on **inside**
the tailnet — device compromise should not equal server access.

Plain HTTP over the tailnet is fine and no TLS is needed: Yattee ships
`NSAppTransportSecurity.NSAllowsArbitraryLoads = true`
(`yattee@main:Yattee/Info.plist`), and Tailscale is already an encrypted
WireGuard transport.

---

## D6 — Terms of Service

This stack extracts YouTube content outside the official client, which violates
YouTube's Terms of Service. That is a durability risk, not a legal-advice
question and not a blocker: it means YouTube actively changes things that break
extraction, and the maintenance path in D3 exists precisely because of it.
Expect breakage on a weeks-to-months cadence and expect to restart the add-on.

---

## Known failure modes

| Symptom | Likely cause | First check |
|---|---|---|
| Every video fails, search still works | yt-dlp broke against YouTube | `verify.sh` → check 2. Restart add-on to pull newer yt-dlp (D3). If a *new* yt-dlp is the regression, set `ytdlp_version` to the last good release. |
| App can't find the server at all | Tailscale down on the Green or the phone | Tailscale add-on log; `tailscale status` on the phone |
| Adding the source returns 401 | Basic Auth credentials wrong, or entered into the URL instead of the prompt | `curl -u user:pass http://<host>:8085/info` |
| Adding the source says "could not detect" | Wrong port, or you gave it the HA URL (8123) rather than the add-on's (8085) | `curl http://<host>:8085/health` |
| Playback stalls at 4K, metadata fine | Streams are relaying through the Green | Turn off `proxy_streaming` for the YouTube site (D2) |
| Trending/Popular/Comments tabs empty | No backing Invidious instance | Expected — see D4 |
| Server unreachable after an HA update | Add-on did not auto-start | HA → Settings → Add-ons → start; confirm "Start on boot" |
| Rapid 401s then 429 | Rate limiter tripped (`rate_limit_max_failures`, default 5 / 60 s) | Wait 60 s, fix the credential, retry |
| Green gets hot / HA sluggish during playback | Relay path active, or download mode writing to tmpfs | `docker stats` via SSH add-on; confirm `proxy_streaming` off |

---

## Docs-vs-code discrepancies found

Where these disagree, the code wins. Flagged as instructed:

1. **`docs/api.md` documents `GET /api/v1/search/suggestions` returning
   `{"query": "...", "suggestions": [...]}`.** The code returns a bare array —
   `routers/search.py:108`, `response_model=List[str]`. The docs are wrong.
2. **`docs/api.md` names `sort` as the search parameter**; that matches the code
   (`search.py:56`) but *not* the Invidious convention `sort_by`, which is what
   Yattee 1.5.1 sends. Relevant only to the rejected client.
3. **`.env.example` documents `SECURE_COOKIES`**, and `config.py:37` reads it —
   but nothing else in the codebase references it. It is dead configuration.
   Harmless; do not expect it to do anything.
4. **`config.py:9` defaults `PORT` to 8080; the Dockerfile sets `ENV PORT=8085`
   but the `CMD` hardcodes `--port 8085`.** So the `PORT` env var does nothing in
   the container. To change the port you must override the command — which is why
   `homeassistant-addon/run.sh` invokes `uvicorn` itself rather than setting `PORT`.
5. **The spec's Phase 3 asked for `/api/v1/stats`.** No such endpoint exists on
   Yattee Server, and Yattee 1.5.1 never calls one (no `stats` reference anywhere
   in the client source). `verify.sh` uses `/health` and `/info` instead.
6. **`/api/v1/captions/{id}` is not reachable with Basic Auth.** `docs/api.md`
   lists `token` as an optional query parameter. It is not optional: the path is
   in `basic_auth.py` `PUBLIC_PATHS`, so the middleware waves it through without
   checking credentials, and then the endpoint demands an HMAC token
   (`invidious_proxy.py:401-415` → `routers/proxy/_auth.py:11-34`). A
   credentialled request with no token gets a flat 401 regardless of server
   health. Clients are meant to use the tokenised caption URLs embedded in the
   video response (`converters/_captions.py:27-75`), which is what Yattee does
   and what `verify.sh` check 6 now does.

---

## What has actually been tested

Recorded so nobody has to guess how much of this is theory. Tested 2026-08-13.

A real `yattee-server` 1.0.7 was run from source on Python 3.12 (the Docker
daemon is unavailable in this environment, so the published image itself was not
run) and driven end to end.

**Confirmed working against the live server:**

- **Env auto-provisioning.** `ADMIN_USERNAME` + `ADMIN_PASSWORD` created the
  admin on first boot — log line `ENV provisioning: created admin user 'admin'`.
  This is the mechanism the add-on's `run.sh` depends on for a reproducible
  deploy.
- **`verify.sh` check 1** passes against a real server and reports
  `server=1.0.7 yt-dlp=2026.07.04` from the authenticated `/info`.
- **Credential rejection is distinguishable from an outage.** With a wrong
  password, check 1 reports `/health ok but /info HTTP 401 — credentials
  rejected` rather than a generic failure.
- **`/info` reports the yt-dlp version** as long as yt-dlp is on the server
  process's `PATH`. It reads `not available` when it is not — an artifact of
  running from a venv, not a defect. The published image pip-installs to
  `/usr/local/bin`, which is on `PATH`.
- **Every Home Assistant Jinja template** in `maintenance/` was rendered against
  the live `/health` and `/info` payloads plus synthesised video responses:
  status, the yt-dlp version including the unauthenticated-stub case, all four
  extraction states, and the `problem` binary sensor across four
  status/extraction combinations. All assertions pass.

**Two real bugs this found and fixed:**

1. `verify.sh` check 6 fetched `/api/v1/captions/{id}` with Basic Auth, which
   always returns 401 (item 6 above). It would have reported FAIL on a perfectly
   healthy server, forever.
2. The yt-dlp sensor used
   `value_json.dependencies['yt-dlp'] | default('unauthenticated')`. The
   `default` filter never fires — subscripting the undefined `dependencies`
   raises first, so the sensor would go `unknown` with a template error instead
   of showing the documented `unauthenticated`. Now uses chained `.get()`.

**Still untested, and only you can close this:**

- Checks 2–7 of `verify.sh`. They need real YouTube extraction, and outbound
  access to YouTube is blocked in the environment this was built in, so every
  one of them returns HTTP 500 here. Their **failure** paths are exercised; their
  **success** paths are not.
- The add-on as Supervisor actually runs it: the image build, `tmpfs` at `/tmp`,
  `/data` persistence, the watchdog, and `run.sh`'s option parsing against a real
  `/data/options.json`.
- Everything in `IPHONE-SETUP.md`.
