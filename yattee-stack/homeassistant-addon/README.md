# Yattee Server — Home Assistant local add-on

Wraps [`yattee/yattee-server`](https://github.com/yattee/yattee-server) as a
Supervisor-managed add-on so it runs on Home Assistant OS the supported way.
Full context in `../README.md` and `../DECISIONS.md`.

## Install

Copy this directory to `/addons/yattee-server/` on the Home Assistant host, then
Settings → Add-ons → Add-on Store → ⋮ → **Check for updates**. It appears under
**Local add-ons**.

## Options

| Option | Default | Notes |
|---|---|---|
| `admin_username` | `admin` | Also the HTTP Basic Auth username the phone uses. |
| `admin_password` | *(empty)* | **Required.** Re-provisioned on every start, so changing it here and restarting changes the real password. Generate with `openssl rand -base64 24`. |
| `invidious_instance_url` | *(empty)* | Leave empty. Adds trending, popular and comments when set; costs you a third-party dependency. See `../DECISIONS.md` D4 and `../probe-invidious.sh`. |
| `ytdlp_version` | `latest` | `latest` upgrades yt-dlp on every start, `skip` uses the image's version, or name a release like `2026.07.04` to pin after a bad one. See `../DECISIONS.md` D3. |
| `log_level` | `info` | uvicorn log level. |

## Files

| File | Purpose |
|---|---|
| `config.yaml` | Add-on manifest. Keys verified against `home-assistant/supervisor@f4ec256` (2026-07-27), `supervisor/apps/validate.py:456-535`. |
| `Dockerfile` | `FROM yattee/yattee-server:1.0.7` pinned by digest, plus the labels Supervisor needs on a non-HA base image. |
| `run.sh` | PID 1. Reads `/data/options.json`, exports the env vars `config.py` expects, refreshes yt-dlp, execs uvicorn. |

## Design notes

- **`init: false`** — the upstream image has no s6 tree, so Supervisor must not
  inject its own init. `run.sh` is PID 1.
- **`tmpfs: true`** mounts a tmpfs at `/tmp`, and `DOWNLOAD_DIR` points there.
  Proxy downloads never touch the Green's 32 GB eMMC.
- **`DATA_DIR=/data/server`** puts the database and encryption key on the
  add-on's persistent volume, which Home Assistant backs up.
- **`run.sh` execs uvicorn directly** rather than deferring to the image's
  `CMD`, because that `CMD` hardcodes `--port 8085` and ignores `$PORT`.
- **`watchdog`** polls `/health`, which is public to Basic Auth
  (`basic_auth.py` `PUBLIC_PATHS`), so Supervisor can reach it without
  credentials.

## Port

`8085/tcp`. Keep it on the tailnet. Do not forward it at the router.
