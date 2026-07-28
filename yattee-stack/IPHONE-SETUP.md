# iPhone setup

Set up Yattee on the phone and confirm it works. Every step has an explicit
pass condition — if a step fails, stop and fix it before moving on, because
later steps assume the earlier ones passed.

**Before you start**, the server side must be done: the Yattee Server add-on is
running on the Home Assistant Green, Tailscale is up on the Green, and
`verify.sh` passes 7/7. See `README.md`.

You will need:

- The server's tailnet address, e.g. `http://green.tailnet-name.ts.net:8085`
- The admin username and password from the add-on's Configuration tab
- iOS 18.0 or newer (18.6+ in your case — fine)

---

## 1. Install Tailscale on the phone

1. App Store → **Tailscale** → install (free).
2. Sign in with the same account as the Green.
3. Settings → confirm the VPN toggle is on and the Green appears in the device
   list.

**Pass:** Safari on cellular data (Wi-Fi off) loads
`http://<green>.<tailnet>.ts.net:8085/health` and shows `{"status":"ok"}`.

**Fail → ** The tailnet name is wrong, or the Green's Tailscale add-on is
stopped. Check Settings → Add-ons → Tailscale → Log on the Green.

> Do this on cellular, not Wi-Fi. On Wi-Fi you may be reaching the LAN address
> and learn nothing about whether Tailscale works.

---

## 2. Install Yattee 2.0 from TestFlight

**Not** the App Store build. The App Store still ships 1.5.1, which predates
Yattee Server by two years and cannot talk to it properly — full reasoning in
`DECISIONS.md` D0.

1. App Store → install **TestFlight** (Apple's own app, free).
2. Open <https://yattee.stream/beta2> on the phone → **Start Testing**.
3. Install Yattee from TestFlight.
4. TestFlight → Yattee → enable **Automatic Updates**.

**Pass:** Yattee opens and shows the onboarding screen. TestFlight lists it as
2.0.0 (build 268 or newer).

**Fail → ** "Beta full" means the 10,000-tester cap is hit; retry in a day or
two. If the build shows an expiry inside a week, a newer build is probably
available — pull to refresh in TestFlight.

> Step 4 is what keeps this off a reinstall treadmill. TestFlight builds stop
> launching 90 days after upload; with auto-updates on, a new build lands every
> few weeks and you never think about it. If you ever open Yattee and it refuses
> to start, open TestFlight and update — that is the whole recovery.

---

## 3. Add the Yattee Server as a source

1. Yattee → Settings → **Sources** → add a source.
2. Enter the URL **without credentials in it**:

   ```
   http://green.<your-tailnet>.ts.net:8085
   ```

   Plain `http` is correct. No TLS is needed: Tailscale is already an encrypted
   WireGuard tunnel, and Yattee permits plain HTTP
   (`NSAllowsArbitraryLoads` in its `Info.plist`).

3. Yattee probes the URL, gets a 401, and asks for credentials. Enter the
   add-on's `admin_username` and `admin_password`.

**Pass:** the source is detected as **Yattee Server** (not Invidious, not
Piped) and saves without an error.

**Fail → **
- *"Could not detect"* — wrong port. `8085` is the add-on; `8123` is Home
  Assistant itself. Confirm with `curl http://<green>:8085/health`.
- *401 after entering credentials* — wrong password. Verify with
  `curl -u admin:<pass> http://<green>:8085/info`; a correct password returns a
  payload containing a `dependencies` key.
- *Repeated 401s then it stops responding* — you tripped the rate limiter
  (5 failures per 60 seconds). Wait a minute.

> Do not embed credentials as `http://user:pass@host`. Yattee 2.0 manages Basic
> Auth credentials itself and expects to prompt.

---

## 4. Play a video — confirm no ads

1. Search for anything with heavy monetisation — a big-channel tech review is
   a good test.
2. Play it.

**Pass:** playback starts with **no pre-roll ad**, and no ad interrupts the
middle of the video. Nothing is skippable because nothing is inserted.

**Fail → ** Run `verify.sh`. If check 2 fails, yt-dlp is broken — see
`maintenance/README.md`.

> There is no ad blocker here and nothing to keep updated. YouTube's ads are
> injected by YouTube's own player; yt-dlp extracts the video stream directly
> and never runs that player. This is why the approach does not decay the way
> a blocklist does.

---

## 5. SponsorBlock

1. Settings → **SponsorBlock** → enable.
2. Enable these categories:
   - **Sponsor** — paid promotions
   - **Self-promotion** — merch and the creator's own plugs
   - **Interaction reminder** — "smash that like button"
   - **Intro** — title animations
   - **Outro** — endcards
   - **Offtopic in music videos** — only matters on music
3. Set the action to **skip automatically** rather than showing a button.

**Pass:** play a video with a known sponsor segment and the player jumps past
it on its own. A reliable test: any recent LTT or Linus Tech Tips upload —
those are densely submitted and near-guaranteed to have segments. Pick one and
watch for the skip in the first two minutes.

**Fail → ** SponsorBlock is entirely client-side: Yattee queries
`sponsor.ajay.app` directly and the server is not involved. So a failure here
means either the categories are off, or that video genuinely has no submitted
segments. Try a more popular video before debugging anything.

---

## 6. Background audio

1. Start a video.
2. Lock the screen.

**Pass:** audio keeps playing. The lock screen and Control Center show the
correct title, channel, and artwork, and the transport controls work.

**Fail → ** Settings → Player → confirm background playback is enabled. If
audio plays but the metadata is blank, that is cosmetic and not worth chasing.

---

## 7. Picture in Picture

1. Start a video.
2. Swipe up to the home screen.

**Pass:** the video shrinks into a floating PiP window and keeps playing. It
survives opening another app.

**Fail → ** Settings → Player → enable PiP, and check iOS Settings → General →
Picture in Picture → **Start PiP Automatically** is on.

---

## 8. Quality — 1080p and 4K

1. Settings → Quality → set the cellular and Wi-Fi profiles.
   Suggested: **1080p on cellular, best available on Wi-Fi**.
2. Play a 4K video on Wi-Fi. Let it run two minutes, then seek forward twice.

**Pass:** no stalling, no repeated rebuffering, and seeking resolves within a
couple of seconds.

**Fail → ** Almost always the stream is relaying through the Green rather than
coming straight from YouTube. Do step 9.

---

## 9. Keep the Green out of the video path

This is a one-time server setting and the single most important tuning step for
this hardware. By default Yattee Server rewrites stream URLs to relay through
itself, and relaying 4K through Python on a fanless Cortex-A55 is the one thing
that will make this setup feel slow.

1. Open the admin panel: `http://<green>:8085/admin`, log in with the same
   credentials.
2. **Sites** → the YouTube entry.
3. Turn **proxy_streaming** off. Save.

**Pass:** replay the 4K video from step 8 — it should now play smoothly. During
playback the Green's CPU should stay low (Settings → System → Hardware in Home
Assistant).

The app's relay fallback still works: when YouTube refuses a direct URL, Yattee
explicitly re-requests with proxying on. You lose nothing by turning the
default off.

---

## 10. If playback breaks later

Check in this order. Each step is cheap and rules out the one below it.

1. **`verify.sh`** — run it first, always. It tells you whether the server or
   the phone is at fault.

   ```sh
   export YS_PASS='...'
   ./verify.sh --url http://<green>:8085 --user admin
   ```

   7/7 means the server is fine and the problem is on the phone or the network.

2. **yt-dlp version** — if `verify.sh` check 2 fails, extraction is broken.
   Restart the add-on to pull the current yt-dlp. If that does not fix it, pin
   `ytdlp_version` to the last good release (`maintenance/README.md`).

3. **Tailscale** — if `verify.sh` cannot reach the server at all, check
   Tailscale on both ends: the add-on log on the Green, and the Tailscale app
   on the phone.

Full symptom table: `DECISIONS.md` → "Known failure modes".
