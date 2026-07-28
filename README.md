# YouTube on iPhone — no ads, no sponsors, free, no weekly reinstall

> ## ⚠️ Superseded — use [`yattee-stack/`](yattee-stack/) instead
>
> The browser-extension approach below does not work in the form it was written
> for. Step 7 of Track 1 is the failure: **iOS does not run Safari Web
> Extensions inside a standalone home-screen web app**, confirmed on-device. You
> can have the fullscreen app feel *or* the blocking, not both. Track 2 (Orion)
> trades uBlock Origin for Orion's own blocker and its extension support is
> still preliminary.
>
> **[`yattee-stack/`](yattee-stack/) is the working setup.** It takes the
> Track 3 idea — Yattee, a native App Store player with SponsorBlock built in —
> and removes the reason Track 3 was only a backup: instead of depending on
> flaky public Invidious instances, it runs a **self-hosted Yattee Server** on
> the Home Assistant Green.
>
> Ads are not blocked; they are never fetched. `yt-dlp` pulls the video stream
> directly, so YouTube's ad-injecting player never runs. Nothing to keep
> updated, no filter lists to decay, plus background audio and PiP.
>
> Start at [`yattee-stack/README.md`](yattee-stack/README.md). The reasoning,
> including why the App Store build of Yattee is the wrong client, is in
> [`yattee-stack/DECISIONS.md`](yattee-stack/DECISIONS.md).
>
> Everything below is kept as a record of what was tried and why it was dropped.

---

A setup that gives you YouTube on an iPhone home screen, launching fullscreen like a real app, with **uBlock Origin killing the ads** and **SponsorBlock skipping the in-video sponsor reads** — the same experience you get on a desktop browser.

Everything installs from the **App Store**, so it auto-updates and never expires. No sideloading, no certificates, no re-signing every 7 days, no money.

---

## Why not just sideload a patched YouTube?

The popular iPhone answer is a patched IPA — uYouPlus, YTLitePlus — installed with AltStore or SideStore. It gets signed with a **free Apple developer certificate that expires after 7 days**, so the app dies weekly until you re-sign it. The ways around that all cost money: the Apple Developer Program is $99/year, and AltStore PAL is EU-only and subscription-based. Jailbreak tweaks like iSponsorBlock don't apply to current iOS.

So this setup skips that whole category. The blocking happens in a browser engine instead of inside Google's native app — which is exactly where uBlock Origin and SponsorBlock were designed to live anyway.

The piece that makes this viable: in August 2025, uBlock Origin's own author shipped **uBlock Origin Lite to the iOS App Store, for free**, and it blocks YouTube ads. Before that, iPhone had no real answer.

---

## Track 1 — Safari (start here)

### 1. Check your iOS version

Settings → General → About. You need **iOS 18.6 or later**. On iOS 26 this works even more cleanly.

### 2. Install uBlock Origin Lite — this handles ads

1. App Store → search **uBlock Origin Lite** (developer: Raymond Hill). Free, about 6 MB.
2. Settings → Apps → Safari → Extensions → **uBlock Origin Lite** → **On**.
3. Set it to **Allow on All Websites**, and pick **Allow**, not "Ask" — otherwise it prompts you constantly.
4. Open the uBlock Origin Lite app itself and set the filtering mode for `youtube.com` to **Optimal** or **Complete**.

> Step 4 is the one people miss. **Basic** mode uses declarative rules only and will miss in-stream video ads. Optimal and Complete inject scripts, which is what actually kills YouTube pre-rolls and mid-rolls.

### 3. Install Userscripts — this hosts SponsorBlock

The official *SponsorBlock for Safari* app is $2.99. This is the free equivalent: run SponsorBlock's logic as a userscript.

1. App Store → search **Userscripts** (open source, by quoid). Free.
2. Open it once and check the directory setting. Recent versions (v1.5.0+) configure a local default folder automatically; older ones will not run anything until you pick one. If prompted, go to Files → On My iPhone → create a folder called `Userscripts` → select it.
3. Settings → Apps → Safari → Extensions → **Userscripts** → **On** → **Allow on All Websites** → **Allow**.

### 4. Add the SponsorBlock script

The script is in this repo: [`userscripts/sponsorblock-mobile.user.js`](userscripts/sponsorblock-mobile.user.js).

> The iOS Userscripts app has **no built-in editor** (unlike the Mac version), so there is nowhere to paste code. You install scripts by pointing Safari at a `.user.js` URL, or by dropping the file in its folder.

On your phone:

1. Open the **raw** file in Safari — on GitHub, tap the file → **Raw**. The URL must end in `.user.js`, which it does:
   `raw.githubusercontent.com/bezanisniko-del/YouTube-Premium-/claude/youtube-mobile-adblock-0x2k73/userscripts/sponsorblock-mobile.user.js`
2. Tap **ᴀA** in Safari's address bar → **Userscripts**.
3. The popup detects the userscript and offers an **install prompt**. Tap it.

**If no install prompt appears,** use the file route instead: **Share** → **Save to Files** → save into the `Userscripts` folder you chose during setup. Keep the `.user.js` ending — if iOS saves it as `.txt`, rename it in Files or the app will ignore it.

It talks to the public SponsorBlock API — the same crowdsourced database the real extension uses. It only sends the first 4 characters of a hash of the video ID, so the server never learns which video you're watching.

Open the file and edit the `SKIP` block at the top if you want different behaviour. Sponsors, self-promo, subscribe-begging, intros, outros and non-music sections are skipped by default; previews and filler are left alone.

### 5. Test in plain Safari — before making it an app

Open `https://m.youtube.com` in Safari, sign in, and play a video you know has both a pre-roll ad and a sponsor read.

- No ad plays → uBlock Origin Lite is working.
- The sponsor segment jumps automatically with a small "Skipped sponsor" notice → the userscript is working.

**Do not move on until both work.** Debug here, in normal Safari, where extensions are guaranteed to run.

### 6. Make it a home screen app

1. In Safari on `m.youtube.com`: **Share** → **Add to Home Screen**.
2. On iOS 26, leave **Open as Web App** switched **on** (it's the default).
3. Name it "YouTube" → **Add**.

You get its own icon, a fullscreen launch with no address bar or Safari toolbar, its own card in the app switcher, and a persistent login. It reads as an app.

### 7. The one test that actually matters

**Apple does not officially support Safari extensions running inside standalone home screen web apps.** On iOS 18+ they appear to carry over, but this is undocumented and Apple could change it.

So: launch YouTube **from the home screen icon** — not from Safari — and replay the same video.

- **Still no ads, sponsors still skipping** → you're done. Nothing to maintain.
- **Ads are back, or sponsors stop skipping** → extensions aren't running in the standalone context. Two options:
  - **Quick:** delete the icon and re-add it with **Open as Web App off**. You lose the chrome-less look but keep one-tap launch and guaranteed blocking.
  - **Better:** go to Track 2.

---

## Track 2 — Orion by Kagi

Worth doing if Track 1's step 7 fails, **or if you want background audio.**

[Orion](https://orionbrowser.com/) is a free App Store browser and the only iOS browser that runs real Chrome and Firefox extensions. Two reasons it's compelling here:

- You get **real SponsorBlock**, not a userscript substitute.
- It does **background audio and Picture-in-Picture for YouTube** — audio keeps playing when you lock the screen or switch apps. Safari won't do this. It's the biggest "feels like the real app" feature, and it's the thing YouTube normally charges Premium for.

> **Do not try to install uBlock Origin here.** Full uBO cannot run on iOS — Apple forces every browser onto WebKit, which only allows MV3-style Safari Web Extensions. Orion's **own built-in ad blocker** is on by default and does that job instead.

1. App Store → **Orion Browser by Kagi**. Free (Orion+ is optional and unnecessary here).
2. Extensions are **off by default and hidden**. Menu → **Settings** → **Advanced** → enable **Chrome and Firefox Extensions**.
3. Menu → **Extensions** → **+** → **Install Chrome Extension** → search **SponsorBlock** → install.
   - It must come from the **Chrome Web Store**. The Firefox add-on store version does not work on Orion.
4. Leave Orion's built-in ad blocking enabled (Settings → ad and tracking blocking).
5. Enable background audio in Orion's settings.
6. Load `m.youtube.com`, sign in, run the step 5 test above.
7. Use Orion's **Add to Home Screen** for the launcher.

Two caveats worth taking seriously. Kagi describes iOS extension support as **preliminary**, so confirm SponsorBlock actually fires rather than trusting that it installed. And Orion's built-in blocker is not the same thing as uBlock Origin Lite — verify it stops YouTube's *in-stream video* ads, not just banners. If either check fails, go back to Track 1; that setup is the reliable one.

---

## Track 3 — Yattee (backup)

[Yattee](https://github.com/yattee/yattee) is a free, open-source, native YouTube client on the App Store with **SponsorBlock built in** and no ads at all — it never loads Google's ad pipeline, so there's nothing to block. Real native app, App Store install, no expiry.

The catch: it pulls content through **Invidious / Piped** community backends, which go down, get rate-limited, and break when YouTube changes things. You also don't get your Google account, subscriptions or history unless you rebuild them in Invidious.

Keep it as a working backup, not the daily driver.

---

## Ruled out, and why

| Option | Why not |
|---|---|
| uYouPlus / YTLitePlus via AltStore or SideStore | Free Apple certs expire in **7 days** |
| AltStore PAL | EU-only, paid subscription |
| Apple Developer Program (1-year certs) | $99/year |
| SponsorBlock for Safari (official) | $2.99 — but it's the cleanest option if you ever relax "free" |
| iSponsorBlock | Needs a jailbreak |
| Full uBlock Origin on Safari | Doesn't exist. iOS only allows MV3-style Safari Web Extensions — uBO **Lite** is the author's real answer |

---

## Verification checklist

Run all of these **from the home screen icon**, not from Safari:

1. **Pre-roll ads** — big-channel video that reliably serves ads. No ad, no "Skip in 5" overlay.
2. **Mid-roll ads** — scrub into the middle of a 20+ minute video. No interruption.
3. **Banner and overlay ads** — no ad cards over the player, no promoted rows in the feed.
4. **SponsorBlock** — play something with a sponsor read. It should jump, with a brief notice.
5. **Session** — force-quit, relaunch from the icon. Still signed in, still blocking.
6. **App feel** — no address bar, no Safari toolbar, own app-switcher card.
7. **Durability** — recheck after the next iOS update and after App Store updates to uBlock Origin Lite or Userscripts.

Expected ongoing maintenance: **none.** If the userscript ever breaks against a YouTube redesign, re-copy it from this repo. That's a two-minute fix, not a weekly ritual.

---

## Troubleshooting

**Ads still playing.** uBlock Origin Lite is probably in Basic mode. Open the app and set `youtube.com` to Optimal or Complete. If they persist, add [`userscripts/youtube-ad-skip.user.js`](userscripts/youtube-ad-skip.user.js) as a second layer — it clicks "Skip Ad" and fast-forwards unskippable ads. It's a backstop, not the primary mechanism, so only add it if you need it.

**Sponsors not skipping.** First open the Userscripts popup on a YouTube page and confirm the script is actually listed and enabled — if the install prompt was dismissed, nothing was installed. Check that Userscripts has a directory set; it silently does nothing without one. Then confirm the script's `@match` lines cover the domain you're on (`m.youtube.com` vs `www.youtube.com`); both are included by default. Also worth knowing: not every video has submitted segments, so test on a large channel where someone has certainly submitted them.

**The install prompt never appears.** The URL has to end in `.user.js` and be the *raw* file — a normal GitHub file page won't trigger it. Fall back to the Save to Files route above.

**Everything works in Safari but not from the home screen icon.** That's the step 7 case — extensions aren't reaching the standalone web app. **Confirmed to happen in practice**, so expect it rather than hoping otherwise. Fix: delete the icon, re-add with **"Open as Web App" off**. You keep one-tap launch and full blocking; you just see the Safari address bar. Track 2 is the alternative if the fullscreen look matters more than certainty.

**Audio stops when I lock the screen.** Expected in Safari. This is what Track 2 (Orion) solves.
