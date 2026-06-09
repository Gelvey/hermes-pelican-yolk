# Custom Pelican Yolk for Hermes Agent
# Based on the official Hermes image, adapted for Pelican Panel's /home/container mount

FROM nousresearch/hermes-agent:latest

# Pelican Panel mounts /home/container for persistent server data.
# Hermes stores its state at /opt/data. We redirect it so data persists across restarts.
USER root
RUN rm -rf /opt/data && ln -s /home/container /opt/data

# Fix s6-overlay permissions error when running as non-root user (Pelican/Pterodactyl
# runs containers as uid 999). s6-overlay preinit expects /run to be owned by the
# container user, not root.
RUN chown -R 999:999 /run /var/run /tmp

# Tell s6-overlay to accept a root-owned /run directory when running as non-root.
# This is a safety net for Pelican/Pterodactyl environments where the runtime user
# may differ from the image build user.
ENV S6_READ_ONLY_ROOT=1

# Ensure /run and /tmp are writable at runtime. Pelican runs containers with a
# read-only root filesystem, but Docker volumes remain writable. Declaring these
# as volumes forces Docker to mount anonymous writable volumes over them, which
# satisfies s6-overlay's requirement for a writable /run directory.
VOLUME ["/run", "/var/run", "/tmp"]

# The Hermes image uses s6-overlay as its init system.
# Our symlink is created at build time so the runtime container starts cleanly.
