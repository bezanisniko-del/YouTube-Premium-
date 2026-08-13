# Handoff prompt for a local Claude Code session

The server-side setup has to run from a machine on the same network as the
Home Assistant Green. A cloud session cannot reach it — see the note at the
bottom.

Start Claude Code **on your PC** (the same way the "Home Assistant setup and
configuration" session ran — `claude` in a terminal), then paste everything
between the lines below.

---

```
I have a Home Assistant Green on my LAN and I want to install a self-hosted
Yattee Server on it as a local add-on. All the files already exist — do not
write them from scratch.

Source of truth:
  https://github.com/bezanisniko-del/YouTube-Premium-
  branch: claude/youtube-adblock-app-plan-ugp00x
  directory: yattee-stack/

Read yattee-stack/README.md and yattee-stack/DECISIONS.md first. DECISIONS.md
explains why this is an add-on rather than docker compose, and why two specific
settings matter. Do not re-litigate those decisions.

Please do the following, checking with me before anything destructive:

1. Find the Home Assistant Green on my network and confirm you can reach it.
   Tell me the address you settled on. If the Advanced SSH & Web Terminal
   add-on is not installed and running with Protection mode off, stop and tell
   me — you need shell access on the host for step 3.

2. Confirm the Tailscale add-on is installed, started, set to start on boot,
   and authenticated. If not, walk me through it — I have to click the auth
   link myself. Tell me the tailnet hostname when it is up.

3. Install the add-on files by running this on the Green's SSH terminal:

     curl -fsSL https://raw.githubusercontent.com/bezanisniko-del/YouTube-Premium-/claude/youtube-adblock-app-plan-ugp00x/yattee-stack/install-addon.sh | bash

   It writes /addons/yattee-server/ and nothing else. Verify the three files
   landed and that run.sh is executable.

4. Tell me to click through: Settings -> Add-ons -> Add-on Store -> three dots
   -> Check for updates, then install "Yattee Server" from Local add-ons.
   Wait for me to confirm. The first build pulls a ~400 MB image and is slow on
   this hardware.

5. Generate a strong admin password with `openssl rand -base64 24`. Show it to
   me once so I can save it. Tell me the exact values to put in the add-on's
   Configuration tab:
     admin_username          admin
     admin_password          <the generated one>
     invidious_instance_url  EMPTY - leave blank
     ytdlp_version           latest
     log_level               info
   Then have me enable "Start on boot" and "Watchdog" and start it. Read the
   add-on log and confirm you see "starting on 0.0.0.0:8085".

6. Run the verification harness from your machine:

     curl -fsSL https://raw.githubusercontent.com/bezanisniko-del/YouTube-Premium-/claude/youtube-adblock-app-plan-ugp00x/yattee-stack/verify.sh -o /tmp/verify.sh
     YS_PASS='<the password>' bash /tmp/verify.sh --url http://<green>:8085 --user admin

   It must report 7/7. If it does not, diagnose it — DECISIONS.md has a
   "Known failure modes" table keyed to each check. Do not move on until it
   passes; a failure here is much cheaper to find than one on the phone.

7. Open http://<green>:8085/admin, log in with the same credentials, go to
   Sites -> the YouTube entry, and turn proxy_streaming OFF. This keeps video
   bytes off the Green, which a fanless Cortex-A55 needs. Confirm it saved.

8. Install the monitoring package:
   - copy yattee-stack/maintenance/yattee_server_package.yaml to
     /config/packages/yattee_server.yaml
   - add to configuration.yaml, if not already present:
       homeassistant:
         packages: !include_dir_named packages
   - add to secrets.yaml:
       yattee_server_user: admin
       yattee_server_pass: <the password>
   - replace both occurrences of homeassistant.local in the package with the
     address from step 1, and all three occurrences of
     notify.mobile_app_iphone with my real notify service (find it in
     Developer Tools -> Actions)
   - Developer Tools -> YAML -> Check configuration, then restart HA
   - confirm sensor.yattee_server_extraction reads "ok" in Developer Tools ->
     States. If it reads "unauthenticated", the secrets are wrong.

When all eight are done, tell me the exact base URL to type into Yattee on my
iPhone, and confirm verify.sh still passes 7/7 after the HA restart.

Print the full verify.sh output verbatim at the end, every check line and the
summary, so I can paste it back to the session that wrote this. Do not
summarise it — the per-check detail is the diagnostic.

Do not touch my phone setup — that is yattee-stack/IPHONE-SETUP.md and I will
do it myself afterwards.
```

---

## Why this can't run from a cloud session

The earlier "Home Assistant setup and configuration" session
(`session_01KVxc8zUdEFHRJ5LnP1Pjk1`, 2026-08-05) reached the Green because it
ran with `environment_kind: bridge` and `origin: claude_code_cli` — the Claude
Code CLI on your own machine, on your own LAN. It did not use a Home Assistant
MCP connector; there isn't one on this account.

Sessions started from the web or the iOS app run with
`environment_kind: anthropic_cloud`, in a container with no route to your LAN
or your tailnet. Verified rather than assumed: TCP connects to
`homeassistant.local:8123`, `homeassistant:8123`, `homeassistant.local:8085`
and a representative LAN address all fail with no route, and `.local` names do
not resolve.

Worth knowing for later: even connecting the official Home Assistant MCP
integration would not close this gap. It exposes **Assist** — reading entity
states and calling services. It has no access to the Supervisor API, so it
cannot install add-ons, write to `/addons`, or edit `configuration.yaml`.
