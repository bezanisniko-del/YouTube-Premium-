# Yattee Server as a Home Assistant local add-on.
#
# Pinned by digest, not by tag: a tag can be repointed, a digest cannot. This is
# yattee/yattee-server:1.0.7, the multi-arch OCI index pushed 2026-07-06
# (Docker Hub, checked 2026-07-28). Docker resolves the aarch64 manifest from
# the index automatically on HA Green.
#
# Since Supervisor 2026.04.0 there is no implicit BUILD_FROM fallback, so the
# FROM is explicit and takes no build arg.
FROM yattee/yattee-server:1.0.7@sha256:e1ccdfa00e460686fa08c66044f6cf5858299c6eb9bdfed749a91c5883853185

# Supervisor requires these on a non-HA base image.
LABEL io.hass.type="addon" \
      io.hass.name="Yattee Server" \
      io.hass.description="Self-hosted yt-dlp backend for the Yattee iOS app" \
      io.hass.version="1.0.7" \
      io.hass.arch="aarch64|amd64"

# Database and encryption keys live on the add-on's persistent /data volume,
# which Home Assistant includes in its backups.
ENV DATA_DIR=/data/server

# tmpfs is mounted at /tmp by the add-on (config.yaml: tmpfs: true), so proxy
# downloads stay in RAM and never wear the eMMC.
ENV DOWNLOAD_DIR=/tmp/yattee-downloads

COPY run.sh /run.sh
RUN chmod +x /run.sh

# init: false in config.yaml means this is PID 1.
CMD ["/run.sh"]
