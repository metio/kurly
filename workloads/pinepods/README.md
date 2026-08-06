<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# pinepods

[PinePods](https://github.com/madeofpendletonwool/PinePods) — a podcast manager
several people share: subscriptions, play positions and downloads live in one
database, so an episode paused on a phone resumes on a laptop. A composable
`kurly.http` workload backed by an external PostgreSQL, with downloaded episodes
and backups on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local pinepods = import 'github.com/metio/kurly/workloads/pinepods/server.libsonnet';

kurly.list(pinepods())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `pinepods` | |
| `image` | `docker.io/madeofpendletonwool/pinepods:v0.6.0` | |
| `storageSize` / `storageClass` | `20Gi` / cluster default | `/opt/pinepods` |
| `dbHost` / `dbPort` / `database` / `dbUser` | `pinepods-db-rw` … | pairs with a `cnpg-cluster` named `pinepods-db` |
| `serverHost` | unset | the host clients reach it on |
| `proxyProtocol` / `reverseProxy` | `http` / `false` | set both behind TLS |
| `searchApiUrl` | the project's own API | podcast search |
| `adminFullname` / `adminUsername` / `adminEmail` | `Pinepods Admin` / `pine-admin` / … | the first administrator |
| `secretName` | `pinepods` | see below |

nginx serves the compiled front end on `:8040` and proxies `/api` to the FastAPI
process on `:8032`, which is never exposed.

## Supply the Secret

```shell
kubectl create secret generic pinepods \
  --from-literal=DB_PASSWORD=… \
  --from-literal=PASSWORD=…
```

`DB_PASSWORD` is the database login. `PASSWORD` is the first administrator's,
created on the first start alongside `adminUsername` and `adminEmail`. Leave it
out and the container invents one **and prints it to the log**, which is a
credential held by everybody who can read logs.

The database named in `database` must already exist — the start-up script creates
the schema and the administrator inside it, not the database itself.

## What it reaches for

- **Podcast search** goes through `searchApiUrl`, the project's own API, over the
  internet. A NetworkPolicy composed onto this workload that forbids egress
  leaves every search empty.
- **The feeds and episodes themselves** are fetched from wherever each podcast
  publishes them.

`serverHost` is the host the API builds the links it hands out from. Left unset,
the container falls back to its own `HOSTNAME`, which here is the pod name —
those links then point at something only the cluster can resolve. Behind an
exposure that terminates TLS, set `proxyProtocol='https'` and `reverseProxy=true`
as well, or the links stay `http://` and a browser refuses them on an https page.

## Less hardened, deliberately

`supervisord` runs nginx, the API and cron together as root, and the entrypoint
chowns the mail spool before any of them start — so root and capabilities are
relaxed. The root filesystem is writable because all three keep their pid, spool
and logs inside the image's own tree.

Service links are off: the Service shares the workload's name, so Kubernetes
would inject `PINEPODS_PORT` as a `tcp://` URL over the value the API builds its
links from.

## Persistence

Downloaded episodes, backups and certificates live on a ReadWriteOnce volume, so
this is **one replica, recreated** (never rolled). Everything else is in
PostgreSQL — point `dbHost` at one that is backed up.

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
metadata: { name: kurly, namespace: pinepods }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-pinepods, namespace: pinepods }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/pinepods, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: pinepods }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-pinepods, namespace: pinepods }
spec: { sourceRef: { kind: OCIRepository, name: kurly-pinepods } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: pinepods, namespace: pinepods }
spec:
  serviceAccountName: pinepods-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/pinepods/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-pinepods, importPath: github.com/metio/kurly/workloads/pinepods }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: pinepods, namespace: pinepods }
spec:
  serviceAccountName: pinepods-deployer
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
        name: pinepods
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: pinepods }
```

<!-- END generated: jaas-deploy -->
