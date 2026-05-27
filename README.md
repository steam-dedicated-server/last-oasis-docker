# Last Oasis Dedicated Server

High-performance, container-first dedicated server for [Last Oasis](https://lastoasis.gg/).

- Multi-stage Docker image (Ubuntu 24.04, ~30–40 % smaller than single-stage)
- Pre-warmed steamcmd → first `install` only pays for the game `app_update`
- `tini` as PID 1 → clean signal forwarding, no zombies, real graceful shutdown
- Pure-Python A2S healthcheck → ~5 ms per probe, no fork/exec overhead
- Single modular `lo` CLI (`install` / `update` / `run` / `backup` / `health`)
- Production-tuned Docker Compose for a single VPS (4 vCPU / 6 GB RAM)
- Kustomize-based Kubernetes bundle (single-node k3s tested)

> Not affiliated with Donkey Crew. Use at your own risk.

---

## Quick start — Docker Compose (single server)

```bash
# 1. Grab the compose file
curl -fLO https://raw.githubusercontent.com/steam-dedicated-server/last-oasis-docker/main/compose/docker-compose.yml

# 2. Replace every <REPLACE_*> placeholder in the `environment` block
$EDITOR docker-compose.yml

# 3. Download game files (one-shot, anonymous Steam — no 2FA)
docker compose --profile maintenance run --rm install

# 4. Start the server
docker compose up -d server

# Day-to-day
docker compose ps                                    # health
docker compose logs -f server                        # tail
docker compose --profile maintenance run --rm update # update game
docker compose --profile maintenance run --rm backup # tar.gz of save data
docker compose down                                  # stop
```

Or use the bundled `Makefile`:

```bash
make install   # download / install
make up        # start
make logs      # tail
make backup    # backup
make down      # stop
```

---

## Repo layout

```
.
├── docker/
│   ├── Dockerfile             # multi-stage Ubuntu 24.04
│   └── healthcheck.py         # Steam A2S query (pure Python)
├── scripts/
│   ├── lo                     # main CLI dispatcher
│   └── lib/
│       ├── common.sh          # logging, retry, traps
│       ├── config.sh          # env loading / validation
│       ├── steam.sh           # steamcmd wrappers
│       ├── server.sh          # server lifecycle
│       └── backup.sh          # save backup
├── config/
│   ├── defaults.env           # baked-in defaults
│   └── server.example.env     # user config template
├── compose/
│   ├── docker-compose.yml         # single-server (primary)
│   └── docker-compose.multi.yml   # multi-map skeleton
├── k8s/                       # kustomize bundle
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── pvc.yaml
│   ├── install-job.yaml
│   ├── deployment.yaml
│   ├── backup-cronjob.yaml
│   └── secret.example.yaml
├── .github/workflows/
│   ├── ci.yml                 # shellcheck + hadolint + build smoke test
│   └── release.yml            # GHCR publish on v*.*.* tags
├── Makefile
├── LICENSE
└── README.md
```

---

## Configuration

| Variable               | Required | Default            | Source                                            |
|------------------------|:--------:|--------------------|---------------------------------------------------|
| `SERVER_CUSTOMER_KEY`  |    ✅    | —                  | myrealm.lastoasis.gg → Settings                    |
| `SERVER_PROVIDER_KEY`  |    ✅    | —                  | myrealm.lastoasis.gg → Settings                    |
| `SERVER_IDENTIFIER`    |    ✅    | —                  | unique within realm                                |
| `SERVER_IP_ADDRESS`    |    ✅    | —                  | host public IPv4                                   |
| `SERVER_PORT`          |    ✅    | `62001`            | unique per IP/realm                                |
| `SERVER_QUERY_PORT`    |    ✅    | `27015`            | unique per IP/realm                                |
| `SERVER_SLOTS`         |          | `10`               | player capacity                                    |
| `STEAM_USER`           |          | `anonymous`        | non-anonymous needs `lo login` once                |
| `SERVER_OPTIONS`       |          | —                  | extra UE CLI flags, appended verbatim              |
| `INSTALL_DIR`          |          | `/data/last-oasis` | install path inside the volume                     |
| `BACKUP_DIR`           |          | `/data/backups`    | tarball destination                                |
| `HEALTHCHECK_TIMEOUT`  |          | `3`                | seconds for A2S probe                              |
| `LO_LOG_LEVEL`         |          | `info`             | `debug` for verbose                                |

Sources of values, in increasing precedence:

1. `config/defaults.env` (baked into image)
2. `config/server.env` or `$LO_CONFIG_FILE` (if present)
3. Compose `environment:` block / k8s `Secret` / shell env

---

## Performance tuning at a glance

| Knob                          | Where                          | Effect                                            |
|-------------------------------|--------------------------------|---------------------------------------------------|
| `seccomp:unconfined`          | compose `security_opt`         | mandatory — steamcmd uses blocked syscalls        |
| `nofile=1048576`              | compose `ulimits`              | high-FD UE server                                 |
| `tmpfs /tmp`                  | compose `tmpfs`                | avoids volume churn from temp files               |
| `cpus`, `memory` limits       | compose `deploy.resources`     | caps a runaway server, keeps host responsive      |
| Pre-warmed steamcmd           | `Dockerfile` build stage       | first runtime `install` is much faster            |
| Multi-stage build             | `Dockerfile`                   | image ~30–40 % smaller than the old single-stage  |
| BuildKit `cache mounts`       | `Dockerfile`                   | re-builds skip apt + steamcmd download            |
| Pure-Python A2S healthcheck   | `docker/healthcheck.py`        | ~5 ms per probe                                   |
| `tini` as PID 1               | `Dockerfile` ENTRYPOINT        | proper signal forwarding, no zombies              |
| `stop_grace_period: 60s`      | compose                        | UE server gets time to flush saves on shutdown    |

Recommended VPS for one 25-slot map: **4 vCPU / 6 GB RAM / 60 GB SSD / 400 Mbps**.

---

## Healthcheck

`docker/healthcheck.py` sends a UDP `A2S_INFO` packet to
`HEALTHCHECK_HOST:SERVER_QUERY_PORT` (default `127.0.0.1:27015`) with a
3-second timeout. The container is marked **unhealthy** after three
consecutive failures — paired with `restart: unless-stopped`, Docker
will recycle a hung server automatically.

---

## Multi-server on one host

Use [`compose/docker-compose.multi.yml`](compose/docker-compose.multi.yml)
as a starting point. Each `server-NN` runs on a distinct port pair and
shares the same `lastoasis-data` volume — install/update once via the
`maintenance` profile, then start all maps.

---

## Kubernetes

```bash
# 1. Render your secret from the example template
cp k8s/secret.example.yaml k8s/secret.yaml
$EDITOR k8s/secret.yaml

# 2. Apply
kubectl apply -f k8s/namespace.yaml
kubectl -n last-oasis apply -f k8s/secret.yaml
kubectl -n last-oasis apply -k k8s/

# 3. Watch
kubectl -n last-oasis get pods -w
kubectl -n last-oasis logs -f deploy/lastoasis-server
```

`Deployment` runs with `hostNetwork: true` so the game ports come
straight off the node's IP. Startup / liveness / readiness probes all
use the same A2S healthcheck.

---

## Releases

Cut a SemVer release and `release.yml` publishes to GHCR:

```bash
git tag v1.0.0
git push origin v1.0.0
```

Published tags: `1.0.0`, `1.0`, `latest`. Images include SBOM and
SLSA provenance attestation.

---

## License

MIT — see [LICENSE](LICENSE).
