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

# ── Create the Pelican data directory early ───────────────────────────
RUN mkdir -p /home/container

# ── User remapping for Pelican compatibility ──────────────────────────
# Pelican Panel runs containers as UID 999. The Hermes image expects a
# "hermes" user (UID 10000) and starts as root so it can usermod at boot.
# Pelican can't start as root, so we remap at build time and patch the
# init scripts to accept non-root starts.
#
# We rename the baked hermes user → container (Pelican's convention) and
# add "hermes" back as an alias so the s6-overlay scripts that reference
# the hermes user by name still find it.
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
    if id hermes >/dev/null 2>&1 && ! id container >/dev/null 2>&1; then \
        usermod -l container hermes; \
        groupmod -n container hermes; \
    fi; \
    \
    # ── Create "hermes" user alias so s6-overlay scripts find the user ──
    if ! id hermes >/dev/null 2>&1; then \
        echo "hermes:x:999:999:Hermes Agent (alias):/opt/data:/sbin/nologin" >> /etc/passwd; \
    fi; \
    \
    # ── Create "hermes" group alias so stage2-hook.sh chown calls work ──
    # stage2-hook.sh uses `chown hermes:hermes` — the group name must resolve.
    # After groupmod -n container hermes above, the hermes group was renamed.
    if ! getent group hermes >/dev/null 2>&1; then \
        echo "hermes:x:999:" >> /etc/group; \
    fi

# ── PATCH 1: Neutralize the UID check in stage2-hook.sh ───────────────
# /opt/hermes/docker/stage2-hook.sh (called by /etc/cont-init.d/01-hermes-setup)
# rejects non-root, non-hermes-UID starts with exit 1. Pelican always starts
# containers as UID 999 (non-root), so this check must be disabled.
# We replace the `if` condition with `if false` — the error block is never entered.
# The end-of-line anchor ($) is intentionally omitted so the match survives
# minor base-image formatting changes (trailing comments, whitespace).
RUN sed -i \
    's/^if \[ "\$cur_uid" != 0 \] && \[ "\$cur_uid" != "\$(id -u hermes)" \]; then/if false; then  # Patched for Pelican (non-root UID 999)/' \
    /opt/hermes/docker/stage2-hook.sh && \
    grep -q 'Patched for Pelican' /opt/hermes/docker/stage2-hook.sh || { \
        echo "ERROR: stage2-hook.sh patch was NOT applied (base image format changed?)" >&2; exit 1; \
    }

# ── PATCH 2: Neutralize the same UID check in main-wrapper.sh ─────────
# /opt/hermes/docker/main-wrapper.sh (the container ENTRYPOINT) has an
# identical check. Same fix with verification.
RUN sed -i \
    's/^if \[ "\$cur_uid" != 0 \] && \[ "\$cur_uid" != "\$(id -u hermes)" \]; then/if false; then  # Patched for Pelican (non-root UID 999)/' \
    /opt/hermes/docker/main-wrapper.sh && \
    grep -q 'Patched for Pelican' /opt/hermes/docker/main-wrapper.sh || { \
        echo "ERROR: main-wrapper.sh patch was NOT applied (base image format changed?)" >&2; exit 1; \
    }

# ── Ensure ownership after all user/group changes ─────────────────────
RUN chown -R 999:999 /home/container /opt/data 2>/dev/null || true

# ── Fix s6-overlay permissions ────────────────────────────────────────
# s6-overlay needs writable /run, /var/run, and /tmp for its supervision
# state. Pelican runs containers with a read-only root filesystem, so we
# declare these as Docker volumes — Docker mounts anonymous writable
# volumes over them at runtime.
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
# Both stage2-hook.sh and main-wrapper.sh have been patched to accept
# Pelican's UID 999 non-root container start.
