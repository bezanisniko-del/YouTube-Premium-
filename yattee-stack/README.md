# Self-hosted YouTube stack for iOS

Ad-free YouTube on the iPhone, with SponsorBlock auto-skip, background audio,
and Picture in Picture — as a normal native app, at no recurring cost, with
nothing to reinstall on a schedule.

## How it works

Ads are not blocked. They are never fetched.

A small server on the Home Assistant Green uses `yt-dlp` to pull video metadata
and stream URLs directly, and hands them to [Yattee](https://yattee.stream), a
native iOS player. YouTube's own player — the thing that injects ads — never
runs. That is why this does not decay the way a blocklist does, and why there
is no extension to keep updated.

```
iPhone (Yattee 2.0)  ──Tailscale──▶  HA Green (Yattee Server add-on, yt-dlp)
       │                                          │
       │                                          └──▶ YouTube (metadata)
       └──────────────────────────────────────────────▶ googlevideo (video bytes, direct)
```

Video bytes go straight from YouTube to the phone. The Green only does
metadata extraction, which is what keeps a fanless Cortex-A55 comfortable.

## What it costs

Nothing. Yattee is free, Yattee Server is MIT, Tailscale's free tier covers
this, and the Green is hardware you already own and already leave running.

## Reinstall cadence

None on a weekly basis. Yattee 2.0 installs via TestFlight with automatic
updates on; new builds land every few weeks and refresh themselves. The only
hard limit is that a TestFlight build stops launching 90 days after upload, so
if upstream ever goes quiet for a full quarter you would open TestFlight and
tap update once. Sideloading — the 7-day treadmill — is not used anywhere here.

## Layout

| Path | What it is |
|---|---|
| `DECISIONS.md` | **Read this first.** The go/no-go on the App Store client, the API coverage matrix, why the Green and not the PC, and the known failure modes. |
| `homeassistant-addon/` | The Home Assistant local add-on. This is the deployment. |
| `IPHONE-SETUP.md` | On-device checklist, ten steps, explicit pass conditions. |
| `verify.sh` | Seven-check regression harness. Run after every yt-dlp bump and first whenever anything breaks. |
| `probe-invidious.sh` | Health-probes the public Invidious instances, if you ever want the optional backing instance. |
| `maintenance/` | HA sensors and automations that catch yt-dlp breakage and push to your phone. |
| `docker-compose.yml`, `.env.example` | Portable fallback for a real Linux Docker host. Not the HA Green path. |

## Bring-up

### 1. Tailscale on the Green

Settings → Add-ons → Add-on Store → **Tailscale** → install, start, enable
"Start on boot", and authenticate via the log link.

Note the tailnet hostname — you need it for the phone.

### 2. Yattee Server add-on

1. Copy `homeassistant-addon/` to `/addons/yattee-server/` on the Green. Use
   the **Samba share** or the **Advanced SSH & Web Terminal** add-on to get at
   that folder.

   > On Home Assistant 2026.07+ the internal path moved to `apps/local`, but the
   > `/addons` share still works — Supervisor keeps the old path linked
   > (`supervisor/bootstrap.py:131`).

2. Settings → Add-ons → Add-on Store → ⋮ → **Check for updates**. "Yattee
   Server" appears under **Local add-ons**.
3. Install. The first build takes a few minutes — it is pulling a 400 MB image
   over a Cortex-A55.
4. **Configuration** tab:
   - `admin_username` — `admin` is fine
   - `admin_password` — generate one, do not reuse: `openssl rand -base64 24`
   - `invidious_instance_url` — **leave empty** (see `DECISIONS.md` D4)
   - `ytdlp_version` — `latest`
5. **Info** tab → enable **Start on boot** and **Watchdog**. Start.
6. Check the Log tab for `starting on 0.0.0.0:8085`.

### 3. Verify

From the SSH add-on, or any machine on the tailnet:

```sh
export YS_PASS='<the admin_password>'
./verify.sh --url http://<green-tailnet-name>:8085 --user admin
```

Expect **7/7**. Do not go to the phone until this passes — every failure is
easier to diagnose here than through the app.

### 4. Turn off stream proxying

Open `http://<green>:8085/admin`, go to **Sites** → YouTube, and turn
**proxy_streaming** off. This keeps video bytes off the Green.
`IPHONE-SETUP.md` step 9 explains why.

### 5. Phone

Follow `IPHONE-SETUP.md`.

### 6. Monitoring

Install the sensors and automations from `maintenance/`. Not optional in
practice — they are what tell you yt-dlp broke, before you find out by trying
to watch something.

## Teardown

- **Stop:** Settings → Add-ons → Yattee Server → Stop.
- **Remove:** Uninstall from the same page. This deletes the add-on's `/data`
  volume, so back it up first if you care about the config.
- **Remove the rest:** delete `/addons/yattee-server/`, remove the sensors and
  automations from `configuration.yaml` / `automations.yaml`, and delete the
  source in Yattee on the phone.

Compose fallback: `docker compose down` to stop, `docker compose down -v` to
also drop the data volume.

## Backup and restore

The add-on's `/data` volume holds the SQLite database and the credential
encryption key. `DATA_DIR=/data/server`.

**Backup** — Settings → System → Backups → Create backup, with the Yattee
Server add-on ticked. HA backs up add-on `/data` volumes as part of a partial
backup. Also fine to leave it to the scheduled full backup, since there is very
little state here.

**Restore** — restore the partial backup from the same screen. Credentials,
site settings, and the encryption key come back together, which matters: the
key decrypts the stored per-site credentials, so restoring the database without
it leaves them unreadable.

**Rebuild from scratch instead** — perfectly reasonable. `admin_username` and
`admin_password` are re-provisioned from the add-on options on every start
(`env_provisioning.py:28-45`), so a fresh install plus turning off
`proxy_streaming` gets you back to a working state in about five minutes.

Compose fallback:

```sh
docker run --rm -v yattee-stack_data:/data -v "$PWD:/backup" alpine \
    tar czf /backup/yattee-data.tar.gz -C /data .
```

## Admin panel

`http://<green>:8085/admin` — HTTP Basic Auth with the same credentials the
phone uses. Settings, per-site config, users, and a browser watch page.

Reachable on the tailnet only. Nothing here is published to the internet: no
forwarded port, no public DNS record, no reverse proxy.

## Terms of service

This extracts YouTube content outside the official client, which violates
YouTube's Terms of Service. Practically, that means YouTube changes things that
break extraction on a weeks-to-months cadence — which is exactly what
`maintenance/` exists to catch. Plan around it; it is not a reason not to build
it, but it is the reason this needs a maintenance story at all.
