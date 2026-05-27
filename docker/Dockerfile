# syntax=docker/dockerfile:1.7
# ============================================================
#  Last Oasis dedicated server image
#  - Multi-stage: pull steamcmd in a downloader stage so the
#    runtime layer cache stays stable across script changes.
#  - tini as PID 1 for clean signal forwarding (no zombies).
#  - Pure-Python A2S healthcheck (no fork/exec overhead).
# ============================================================

# ---------- Stage 1: steamcmd downloader ----------
FROM ubuntu:24.04 AS steamcmd

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates curl

WORKDIR /opt/steamcmd
RUN curl -fsSL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" \
    | tar -xz


# ---------- Stage 2: runtime ----------
FROM ubuntu:24.04 AS runtime

ARG STEAM_UID=1000
ARG STEAM_GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    IN_DOCKER=1 \
    HOME=/data \
    PATH=/opt/lastoasis/scripts:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      lib32gcc-s1 \
      lib32stdc++6 \
      python3-minimal \
      tini && \
    rm -rf /var/lib/apt/lists/*

# Ubuntu 24.04 ships a default `ubuntu` user at UID/GID 1000.
# Reclaim that UID for `steam` so volumes built on earlier
# base images keep matching ownership.
RUN if id ubuntu >/dev/null 2>&1; then userdel --remove ubuntu; fi && \
    if getent group ubuntu >/dev/null;   then groupdel ubuntu;   fi && \
    groupadd --system --gid "${STEAM_GID}" steam && \
    useradd  --system --uid "${STEAM_UID}" --gid steam \
             --home-dir /home/steam --shell /usr/sbin/nologin \
             --create-home steam

# Persistent data volume (game files, saves, steamcmd state).
# HOME is set to /data so steamcmd's ~/.steam lands inside the volume.
RUN install -d -o steam -g steam -m 0755 /data
VOLUME ["/data"]

# steamcmd binary lives in the image (NOT in /data) so volume mounts
# don't shadow it.
COPY --from=steamcmd --chown=steam:steam /opt/steamcmd /home/steam/steamcmd

# App files — order matters for layer caching:
#   1. healthcheck (rarely changes)
#   2. config defaults
#   3. libraries
#   4. main CLI (changes most often)
WORKDIR /opt/lastoasis
COPY --chown=steam:steam --chmod=0755 docker/healthcheck.py ./healthcheck.py
COPY --chown=steam:steam config/                            ./config/
COPY --chown=steam:steam scripts/lib/                       ./scripts/lib/
COPY --chown=steam:steam --chmod=0755 scripts/lo            ./scripts/lo

USER steam

# Pre-warm steamcmd: downloads its own bootstrap files now so the
# first runtime `install` only pays for the Last Oasis app_update.
RUN /home/steam/steamcmd/steamcmd.sh +quit || true

EXPOSE 62001/udp 62001/tcp 27015/udp 27015/tcp

HEALTHCHECK --interval=30s --timeout=5s --start-period=180s --retries=3 \
  CMD python3 /opt/lastoasis/healthcheck.py || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/opt/lastoasis/scripts/lo"]
CMD ["help"]
