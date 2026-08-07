# Maintenance

yt-dlp breaks against YouTube on a weeks-to-months cadence. This directory is
the automation that catches it before you do.

## What runs

| File | What it gives you |
|---|---|
| **`yattee_server_package.yaml`** | **Start here.** Everything below in one drop-in package file — one file to add, one line in `configuration.yaml`. |
| `rest_sensors.yaml` | Three REST sensors plus a `problem` binary sensor. The one that matters is `sensor.yattee_server_extraction`, which does a real extraction every 30 minutes — `/health` stays green when yt-dlp breaks, so liveness alone would tell you nothing. |
| `automations.yaml` | Nightly add-on restart at 04:00 (which is how the yt-dlp upgrade happens — see `DECISIONS.md` D3), a 15-minute-sustained unhealthy alert, and a recovery dismissal. |

Use **either** the package file **or** the two separate files — not both, or you
get duplicate entities. The package is the same content and less to get wrong;
the split files exist if you already keep `rest:` and `automation:` organised
your own way.

Failures raise a persistent notification **and** a companion-app push. Success
is silent on purpose: a nightly "all good" push is a nightly push you learn to
swipe away.

Nothing auto-rolls-back. A bad yt-dlp release is surfaced with the version
number and the instruction to pin, never quietly reverted.

## Install — package file (recommended)

1. Copy `yattee_server_package.yaml` to `/config/packages/yattee_server.yaml`.
2. Add to `configuration.yaml`, if you do not already have a `packages:` line:

   ```yaml
   homeassistant:
     packages: !include_dir_named packages
   ```

3. Then steps 1, 3, 4 and 5 below (secrets, host, notify service, restart).

## Install — separate files

1. Add the credentials to `secrets.yaml`:

   ```yaml
   yattee_server_user: admin
   yattee_server_pass: <the add-on's admin_password>
   ```

2. Merge `rest_sensors.yaml` into `configuration.yaml`. If you already have
   `rest:` or `template:` keys, merge the list items — YAML will not let you
   declare either key twice.

3. Fix the host. Both files use `homeassistant.local:8085`. Use your tailnet
   name or the LAN IP. **Not** `127.0.0.1` — that resolves inside the HA Core
   container, not on the host where the add-on's port lives.

4. Merge `automations.yaml` into `automations.yaml`, and replace
   `notify.mobile_app_iphone` with your real service name (Developer Tools →
   Actions → search `notify`).

5. Developer Tools → YAML → Check configuration, then Restart.

6. Confirm `sensor.yattee_server_extraction` reads `ok` in Developer Tools →
   States. If it reads `unauthenticated`, the secrets are wrong.

## Add-on slug

The automations target `local_yattee_server` — `local_` plus the `slug` from
`config.yaml`. If you renamed the directory or the slug, update it. Settings →
Add-ons → Yattee Server, and read it off the URL.

## Manual recovery from a yt-dlp break

The nightly restart already tries the newest yt-dlp. When the newest yt-dlp is
itself the problem:

1. Run the full check to see what actually broke:

   ```sh
   export YS_PASS='...'
   ./verify.sh --url http://<green>:8085 --user admin
   ```

2. Find a good release at <https://github.com/yt-dlp/yt-dlp/releases>. Working
   backwards from the last version that worked is faster than bisecting.

3. Add-on → Configuration → set `ytdlp_version` to that release, e.g.
   `2026.07.04`. Save, restart.

4. Re-run `verify.sh`. Expect 7/7.

5. Leave it pinned until upstream ships a fix, then set it back to `latest`.
   A forgotten pin is its own outage three months later — the nightly log entry
   records the running version, so check it occasionally.

To test a version without committing to it, `ytdlp_version: skip` falls back to
whatever the image shipped (2026.07.04 for image tag 1.0.7).

## When the add-on itself needs updating

The image is pinned by digest in `homeassistant-addon/Dockerfile`. It does not
move on its own — deliberately, since an unattended image bump can change more
than yt-dlp.

To take a new upstream release: check
<https://hub.docker.com/r/yattee/yattee-server/tags>, update both the tag and
the digest in the `FROM`, bump `version:` in `config.yaml` so Supervisor offers
the update, rebuild, then run `verify.sh`.
