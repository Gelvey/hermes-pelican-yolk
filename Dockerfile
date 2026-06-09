# ----------------------------------
# Pelican Panel Custom Yolk
# Environment: Hermes Agent
# Minimum Panel Version: 1.0.0
# ----------------------------------
# Build with:
#   docker build --build-arg TARGETOS=linux --build-arg TARGETARCH=amd64 -t ghcr.io/gelvey/hermes-pelican:latest .
# Or use the GitHub Actions workflow for automated multi-platform builds.
ARG TARGETOS=linux
ARG TARGETARCH=amd64
FROM --platform=${TARGETOS}/${TARGETARCH} nousresearch/hermes-agent:latest

LABEL org.opencontainers.image.authors="gelvey@neuronexus.xyz" \
      org.opencontainers.image.source="https://github.com/gelvey/hermes-pelican" \
      org.opencontainers.image.licenses=MIT \
      org.opencontainers.image.description="Custom Yolk for Hermes Agent on Pelican Hosting Panel"

# ── Pelican Panel mounts /home/container for persistent server data.
# ── Hermes stores its state at /opt/data. We redirect it so data survives restarts.
USER root
RUN rm -rf /opt/data && ln -s /home/container /opt/data

# ── Create the Pelican data directory early so it exists for ownership fixes ──
RUN mkdir -p /home/container

# ── User remapping for Pelican compatibility ──────────────────────────
# Pelican Panel runs containers as UID 999. The Hermes image expects the
# "hermes" user to exist and its s6-overlay init scripts check that the
# runtime user IS the hermes user. We remap hermes → UID 999 at build time.
#
# We also rename the user to "container" and the group to "container" to
# satisfy Pelican's convention, then create a "hermes" alias so that
# Hermes's own init scripts still find a user named "hermes".
RUN set -eux; \
    # ── Capture the original hermes UID/GID ──
    OLD_UID=$(id -u hermes 2>/dev/null || echo ""); \
    OLD_GID=$(id -g hermes 2>/dev/null || echo ""); \
    \
    # ── Remap the hermes user and group to UID/GID 999 ──
    if [ -n "$OLD_UID" ] && [ "$OLD_UID" != "999" ]; then \
        usermod -o -u 999 hermes; \
    fi; \
    if [ -n "$OLD_GID" ] && [ "$OLD_GID" != "999" ]; then \
        groupmod -o -g 999 hermes; \
    fi; \
    \
    # ── Fix ownership of Hermes files that were owned by the old UID ──
    if [ -n "$OLD_UID" ] && [ "$OLD_UID" != "999" ]; then \
        find /opt/hermes -user "$OLD_UID" -exec chown -h 999:999 {} + 2>/dev/null || true; \
    fi; \
    \
    # ── Rename hermes → container (Pelican convention) ──
    # Use usermod/groupmod -l (login/group rename) which properly updates
    # all system files (passwd, shadow, group, gshadow, subuid, subgid).
    if id hermes >/dev/null 2>&1 && ! id container >/dev/null 2>&1; then \
        usermod -l container hermes; \
        groupmod -n container hermes; \
    fi; \
    \
    # ── Create "hermes" alias so Hermes init scripts find the user ──
    # Hermes s6-overlay scripts look for a user named "hermes".
    # Add it as an alias entry with the same UID/GID 999.
    if ! id hermes >/dev/null 2>&1; then \
        echo "hermes:x:999:999:Hermes Agent (alias):/opt/data:/sbin/nologin" >> /etc/passwd; \
    fi

# ── Ensure ownership after all user/group changes ─────────────────────
RUN chown -R 999:999 /home/container /opt/data 2>/dev/null || true

# ── Fix s6-overlay permissions ────────────────────────────────────────
# s6-overlay needs writable /run, /var/run, and /tmp for its supervision
# state. Pelican runs containers with a read-only root filesystem, so we
# declare these as Docker volumes — Docker mounts anonymous writable
# volumes over them at runtime, satisfying both s6 and Pelican.
RUN chown -R 999:999 /run /var/run /tmp 2>/dev/null || true; \
    chmod 755 /run /var/run /tmp 2>/dev/null || true

# Tell s6-overlay to accept a root-owned /run directory when running as non-root.
ENV S6_READ_ONLY_ROOT=1

# Declare writable volumes so Docker overrides the read-only rootfs
VOLUME ["/run", "/var/run", "/tmp"]

# ── Runtime user ──────────────────────────────────────────────────────
# Use the container user (UID 999). Hermes's init scripts check for the
# "hermes" user (now an alias to the same UID).
ENV USER=container HOME=/home/container
WORKDIR /home/container
USER container

# Signal handling for graceful shutdown
STOPSIGNAL SIGTERM

# The Hermes image's s6-overlay ENTRYPOINT is inherited from the base image.
# The startup command is passed via Pelican's egg configuration.
