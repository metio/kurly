<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# onloc

[Onloc](https://onloc.app) — devices report where they are and this keeps the
record, so the companion application can show them on a map. A plain composable
`kurly.http` workload on the official image, backed by an external PostgreSQL,
with uploaded avatars on a PersistentVolume.

This is the **API only**. The web interface is a separate image and is not
carried here; the API serves the REST endpoints, the websocket and `/uploads`.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local onloc = import 'github.com/metio/kurly/workloads/onloc/server.libsonnet';

kurly.list(onloc())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `onloc` | |
| `image` | `ghcr.io/onloc-app/onloc-api:1.2.7` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | `/app/uploads` |
| `secretName` | `onloc` | `DATABASE_URL`, `ACCESS_TOKEN_SECRET`, `REFRESH_TOKEN_SECRET` |
| `env` / `resources` / `labels` / `annotations` | | |

## The database

PostgreSQL, addressed as a Prisma connection URL with the password in it, so the
whole `DATABASE_URL` lives in the Secret rather than being assembled from parts.
The defaults pair with a `cnpg-cluster` named `onloc-db`:

```jsonnet
kurly.list([
  (import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet')(name='onloc-db'),
  onloc(),
])
```

## The Secret, and why the token secrets matter

Both token secrets **fall back to values published in the source** when unset —
`onloc-access-token-secret` and `onloc-refresh-token-secret`. A deployment that
leaves them out is one where anybody who has read the repository can mint a valid
token, so supplying them is not hardening, it is the difference between having
accounts and not:

```shell
kubectl create secret generic onloc \
  --from-literal=DATABASE_URL='postgresql://onloc:PASSWORD@onloc-db-rw:5432/onloc?schema=public' \
  --from-literal=ACCESS_TOKEN_SECRET="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')" \
  --from-literal=REFRESH_TOKEN_SECRET="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
```

## First start runs the migrations

The container applies the Prisma migrations before it serves, which on an empty
database takes longer than a liveness probe should wait. That budget is a startup
probe, not a longer liveness delay — a `StageSet` deploying this needs a `timeout`
past it too.

## Persistence

Uploaded avatars on a ReadWriteOnce volume; everything else is in PostgreSQL. That
makes this **one replica, recreated** (never rolled).

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
metadata: { name: kurly, namespace: onloc }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-onloc, namespace: onloc }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/onloc, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: onloc }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-onloc, namespace: onloc }
spec: { sourceRef: { kind: OCIRepository, name: kurly-onloc } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: onloc, namespace: onloc }
spec:
  serviceAccountName: onloc-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/onloc/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-onloc, importPath: github.com/metio/kurly/workloads/onloc }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: onloc, namespace: onloc }
spec:
  serviceAccountName: onloc-deployer
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
        name: onloc
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: onloc }
```

<!-- END generated: jaas-deploy -->
