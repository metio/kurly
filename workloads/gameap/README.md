<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# gameap

[GameAP](https://gameap.com/) — the web panel and API that administer game
servers running on Linux and Windows hosts. The panel talks to a GameAP daemon
on every node over gRPC; this workload carries the panel, a single static binary
on the project's own image, with its database and uploaded files on a
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local gameap = import 'github.com/metio/kurly/workloads/gameap/server.libsonnet';

kurly.list(gameap())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `gameap` | |
| `image` | `docker.io/gameap/gameap:4.5.0` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | `/var/lib/gameap` — database and files |
| `databaseDriver` | `sqlite` | `sqlite`, `postgres` or `mysql` |
| `databaseUrl` | unset | the connection URL; from the Secret for an external server |
| `secretName` | `gameap` | Secret with `ENCRYPTION_KEY` and `AUTH_SECRET` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the panel, the REST API and the WebSocket endpoint on `:8025` — compose an
exposure onto it.

## Database and secrets

GameAP speaks **SQLite**, **PostgreSQL** or **MySQL/MariaDB**. It defaults to
SQLite on its own volume, so it needs nothing external to start. For an external
server set `databaseDriver` to `postgres` or `mysql` and leave `databaseUrl`
unset: that URL carries the password, so it belongs in the Secret alongside the
other two keys rather than in a rendered manifest. The
[cnpg-cluster](../cnpg-cluster/) and [mysql-cluster](../mysql-cluster/) workloads
provide a server.

`ENCRYPTION_KEY` encrypts the credentials the panel stores for the nodes it
manages, and `AUTH_SECRET` signs the session tokens — rotating either logs
everyone out, and changing `ENCRYPTION_KEY` makes the stored credentials
unreadable. Both come from a provided Secret via `envFrom`; kurly authors **no
Secret**.

`FILES_DRIVER` is `local`, writing under the volume. The panel also supports S3,
which is what a horizontally scaled deployment needs; setting it is an `env`
override away, but the volume it then no longer needs is still claimed here.

## Security and persistence

The image ships a single static binary running as an unprivileged user, and the
panel serves plain HTTP on an unprivileged port when something else terminates
TLS. Nothing needs relaxing: non-root, a read-only root filesystem, no privilege
escalation and all capabilities dropped all stand. The image names that user
rather than numbering it, which kubelet cannot check against `runAsNonRoot`, so
the uid the image creates (`1000`) is named here, with a matching `fsGroup` so
the volume arrives owned by it. A small init container running the same image
creates the file-manager directory on that volume — the panel opens its base
path at startup and panics when it is not there. Every variable it reads is
unprefixed (`HTTP_PORT`, `DATABASE_URL`), so service links are disabled to keep
Kubernetes' injected `GAMEAP_PORT` out of the same namespace of names.

The SQLite database and the uploaded files live on a **ReadWriteOnce** volume, so
this is a single writer: one replica, recreated rather than rolled, to keep two
pods off the same files.

`/api/health` is answered without authentication and is what the probes read; the
first start creates the schema, which the startup probe waits out.

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
metadata: { name: kurly, namespace: gameap }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-gameap, namespace: gameap }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/gameap, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: gameap }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-gameap, namespace: gameap }
spec: { sourceRef: { kind: OCIRepository, name: kurly-gameap } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: gameap, namespace: gameap }
spec:
  serviceAccountName: gameap-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/gameap/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-gameap, importPath: github.com/metio/kurly/workloads/gameap }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: gameap, namespace: gameap }
spec:
  serviceAccountName: gameap-deployer
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
        name: gameap
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: gameap }
```

<!-- END generated: jaas-deploy -->
