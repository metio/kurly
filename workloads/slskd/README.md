<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# slskd

[slskd](https://github.com/slskd/slskd) — a web-based client for the Soulseek
file sharing network: search the network, queue downloads, and share your own
files back. A plain composable `kurly.http` workload keeping its configuration,
SQLite databases and downloads on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local slskd = import 'github.com/metio/kurly/workloads/slskd/server.libsonnet';

kurly.list(slskd())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `slskd` | |
| `image` | `slskd/slskd:0.26.0` | |
| `storageSize` / `storageClass` | `20Gi` / cluster default | `/app` — config, databases, downloads |
| `secretName` | `slskd` | the Soulseek account, the web login, the JWT key |
| `https` | `false` | slskd's own TLS listener |
| `env` / `resources` / `labels` / `annotations` | | |

## The Secret

Two different logins live in it, and they are easy to confuse. `SLSKD_SLSK_*` is
an account **on the public Soulseek network** — you register it with Soulseek,
kurly cannot mint it. `SLSKD_USERNAME` / `SLSKD_PASSWORD` are the local web
login. `SLSKD_JWT_KEY` signs the tokens the web UI holds; slskd generates one at
startup when it is unset, which logs everybody out on every restart.

```shell
kubectl create secret generic slskd \
  --from-literal=SLSKD_SLSK_USERNAME=<your soulseek account> \
  --from-literal=SLSKD_SLSK_PASSWORD=<your soulseek password> \
  --from-literal=SLSKD_USERNAME=admin \
  --from-literal=SLSKD_PASSWORD="$(head -c 24 /dev/urandom | base64)" \
  --from-literal=SLSKD_JWT_KEY="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
```

## The peer port is not decoration

Beside the web port the Service carries `peer` on `:50300`. Soulseek peers
connect **inward** on it. Without a route from the internet to that port the
client still works — it logs in, searches, and downloads from peers that can
accept an outbound connection — but transfers with firewalled peers never start,
and the failure looks like slow queues rather than a networking problem.

It also needs plain egress: it is a client of a public network, so a
NetworkPolicy derived from the shape of the manifest blocks the one thing it does.

```jsonnet
slskd() + kurly.network.kubernetes(
  allowTo=[{ cidr: '0.0.0.0/0' }],
  allowFrom=[{ cidr: '0.0.0.0/0', ports: [50300] }],
)
```

## HTTPS

slskd can serve TLS itself, from a self-signed certificate it mints into its data
directory — which no browser and no ingress will verify. It is off by default
here (`SLSKD_NO_HTTPS`) because the cluster terminates TLS at the exposure. Pass
`https=true` if you have a reason to run its own listener as well.

## Shares and downloads

Downloads land under `/app/downloads` on the volume, so `storageSize` is sized
for them rather than for configuration. Point `SLSKD_SHARED_DIR` at whatever you
mean to share and compose the volume carrying it on — sharing nothing back is
noticed by other users of the network.

## Persistence

SQLite on a ReadWriteOnce volume, so this is **one replica, recreated** (never
rolled).

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**e2e** — this workload is deployed to a live cluster by a smoke scenario and observed reaching readiness, on top of its test coverage.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stage with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
are single-layer, so a plain Flux `OCIRepository` pulls each one directly.

```yaml
# The kurly library (recipes) and this workload (source), both single-layer
# images from their release pipelines, pulled by plain OCIRepositories.
#
# Pinned by VERSION, not by `latest`: a moveable tag means the source you
# render can change under you between reconciles, and there is no saying
# afterwards which one produced what is running. Renovate keeps these
# current, and can pin the digest on top if reproducibility has to survive a
# retagged registry. The catalog names the version each release published.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: slskd }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-slskd, namespace: slskd }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/slskd, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: slskd }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-slskd, namespace: slskd }
spec: { sourceRef: { kind: OCIRepository, name: kurly-slskd } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: slskd, namespace: slskd }
spec:
  serviceAccountName: slskd-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/slskd/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-slskd, importPath: github.com/metio/kurly/workloads/slskd }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: slskd, namespace: slskd }
spec:
  serviceAccountName: slskd-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: slskd
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: slskd }
```

<!-- END generated: jaas-deploy -->
