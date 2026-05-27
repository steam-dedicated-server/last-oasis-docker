# Kubernetes deployment

Production-ready manifests for running one Last Oasis dedicated server
on a single Kubernetes node.

## Prerequisites

- A node with at least **4 vCPU / 6 GB RAM / 60 GB free disk**
- Public IPv4 reachable from the internet (the Deployment uses `hostNetwork: true`)
- `kubectl` configured against the target cluster
- Optional: `kustomize` (or just use `kubectl apply -k`)

## Bundle contents

| File | Purpose |
|---|---|
| [`pvc.yaml`](pvc.yaml) | 30 Gi persistent volume for game files + saves |
| [`install-job.yaml`](install-job.yaml) | One-shot Job that runs `steamcmd app_update` |
| [`deployment.yaml`](deployment.yaml) | The actual game server (replicas: 1, Recreate) |
| [`backup-cronjob.yaml`](backup-cronjob.yaml) | Daily 04:00 UTC `tar.gz` of `Mist/Saved/` |
| [`secret.example.yaml`](secret.example.yaml) | Template for the per-server config Secret |
| [`kustomization.yaml`](kustomization.yaml) | Glue for `kubectl apply -k k8s/` |

## Deploy

```bash
# 1. Create the namespace (kept out of the kustomize bundle so the
#    same manifests work with whatever namespace policy you prefer).
kubectl create namespace last-oasis

# 2. Render and apply the Secret with your realm keys / IP / ports.
#    secret.yaml is git-ignored — don't commit it.
cp k8s/secret.example.yaml k8s/secret.yaml
$EDITOR k8s/secret.yaml
kubectl -n last-oasis apply -f k8s/secret.yaml

# 3. Apply the rest of the bundle (PVC, install Job, Deployment, CronJob).
kubectl -n last-oasis apply -k k8s/

# 4. Watch the install Job finish before the Deployment becomes ready.
kubectl -n last-oasis logs -f job/lastoasis-install
kubectl -n last-oasis get pods -w
```

The Deployment uses `hostNetwork: true`, so the game (62001/udp+tcp) and
Steam query (27015/udp) ports come straight off the node's IP. Make sure
those are open on any firewall in front of the node.

## Day 2

```bash
# Tail server logs
kubectl -n last-oasis logs -f deploy/lastoasis-server

# Trigger a manual update (re-runs the same install Job)
kubectl -n last-oasis delete job lastoasis-install --ignore-not-found
kubectl -n last-oasis apply -f k8s/install-job.yaml

# Trigger a manual backup outside the daily schedule
kubectl -n last-oasis create job --from=cronjob/lastoasis-backup lastoasis-backup-manual

# Drop into a shell on the running pod
kubectl -n last-oasis exec -it deploy/lastoasis-server -- bash
```

## Customising for multiple maps

Each map needs its own PVC + Deployment + Job + ports + Secret. Common
pattern: copy this bundle per map, edit the resource names and
`hostPort` numbers, and pin each Deployment to a specific node via
`nodeSelector: { oasis: <name> }`. See the commented `nodeSelector`
block in [`deployment.yaml`](deployment.yaml).

## Teardown

```bash
kubectl -n last-oasis delete -k k8s/
kubectl -n last-oasis delete secret lastoasis-config
kubectl delete namespace last-oasis
```

The PVC will go away with the namespace — including your save data.
Run `lo backup` (via the CronJob or `kubectl create job --from=...`)
first if you want to keep it.
