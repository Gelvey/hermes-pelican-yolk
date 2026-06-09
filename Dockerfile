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

# Create the required Pelican container user with UID 999 (harmless if it already exists)
RUN groupadd -g 999 container 2>/dev/null || true && \
    useradd -u 999 -g 999 -m -d /home/container -s /bin/bash container 2>/dev/null || true

# Fix s6-overlay permissions error when running as non-root user.
# Pelican runs containers as the 'container' user, so s6-overlay preinit expects
# /run to be owned by that user, not root.
RUN chown -R 999:999 /run /var/run /tmp && chmod 777 /run /var/run /tmp

# Tell s6-overlay to accept a root-owned /run directory when running as non-root.
# This is a safety net for Pelican/Pterodactyl environments where the runtime user
# may differ from the image build user.
ENV S6_READ_ONLY_ROOT=1

# Ensure /run and /tmp are writable at runtime. Pelican runs containers with a
# read-only root filesystem, but Docker volumes remain writable. Declaring these
# as volumes forces Docker to mount anonymous writable volumes over them, which
# satisfies s6-overlay's requirement for a writable /run directory.
VOLUME ["/run", "/var/run", "/tmp"]

# Set the default user and working directory as required by Pelican
ENV USER=container HOME=/home/container
WORKDIR /home/container
USER container

# Signal handling for graceful shutdown
STOPSIGNAL SIGINT

# The Hermes image uses s6-overlay as its init system.
# Our symlink is created at build time so the runtime container starts cleanly.
