# ----------------------------------
# Pelican Panel Custom Yolk
# Environment: Hermes Agent
# Minimum Panel Version: 1.0.0
# ----------------------------------
FROM --platform=$TARGETOS/$TARGETARCH nousresearch/hermes-agent:latest

LABEL org.opencontainers.image.authors="gelvey@neuronexus.xyz" \
      org.opencontainers.image.source="https://github.com/gelvey/hermes-pelican" \
      org.opencontainers.image.licenses=MIT \
      org.opencontainers.image.description="Custom Yolk for Hermes Agent on Pelican Hosting Panel"

# Pelican Panel mounts /home/container for persistent server data.
# Hermes stores its state at /opt/data. We redirect it so data persists across restarts.
USER root
RUN rm -rf /opt/data && ln -s /home/container /opt/data

# The Hermes image is designed to start as root, remap the hermes user, and then
# drop privileges via s6-setuidgid. Pelican runs containers as UID 999, so the
# image's root checks in stage2-hook.sh and main-wrapper.sh fail because
# 999 != 0 and 999 != 10000 (the baked hermes UID). The fix: remap the hermes
# user to UID 999 at build time so the runtime UID matches the hermes user.
# Then the root checks pass naturally, and the scripts skip usermod/groupmod
# because the desired UID is already in place.
RUN old_uid=$(id -u hermes) && old_gid=$(id -g hermes) && \
    usermod -o -u 999 hermes && \
    groupmod -o -g 999 hermes && \
    find /opt/hermes -user "$old_uid" -exec chown -h 999:999 {} + 2>/dev/null || true

# Create the Pelican data directory and ensure it's owned by the runtime user.
RUN mkdir -p /home/container && chown 999:999 /home/container

# Fix s6-overlay permissions error when running as non-root user.
# Pelican runs containers as UID 999, so s6-overlay preinit expects /run to be
# owned by the runtime user, not root.
RUN chown -R 999:999 /run /var/run /tmp && chmod 777 /run /var/run /tmp

# Tell s6-overlay to accept a root-owned /run directory when running as non-root.
ENV S6_READ_ONLY_ROOT=1

# Ensure /run and /tmp are writable at runtime. Pelican runs containers with a
# read-only root filesystem, but Docker volumes remain writable. Declaring these
# as volumes forces Docker to mount anonymous writable volumes over them.
VOLUME ["/run", "/var/run", "/tmp"]

# Use the hermes user (now UID 999) as the runtime user. The Hermes image's
# init scripts and service run files expect the runtime user to be hermes.
ENV USER=hermes HOME=/opt/data
WORKDIR /home/container
USER hermes

# Signal handling for graceful shutdown
STOPSIGNAL SIGTERM

# The Hermes image uses s6-overlay as its init system.
# Our symlink is created at build time so the runtime container starts cleanly.
