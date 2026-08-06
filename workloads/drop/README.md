<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# drop

[Drop](https://droposs.org) — a distribution platform for DRM-free games: an
imported library, a store front for the people you share it with, and a desktop
client that installs and updates from it. A composable `kurly.http` workload
backed by an external PostgreSQL, with the game library and the object store on
PersistentVolumes.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local drop = import 'github.com/metio/kurly/workloads/drop/server.libsonnet';

kurly.list(drop(externalUrl='https://games.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `drop` | |
| `image` | `ghcr.io/drop-oss/drop:0.4.0-rc-5` | |
| `librarySize` | `100Gi` | `/library` — the games you import |
| `dataSize` | `10Gi` | `/data` — the file-system object store |
| `storageClass` | cluster default | both volumes |
| `externalUrl` | unset | the public URL clients are handed |
| `secretName` | `drop` | holds `DATABASE_URL` |

## Supply the database and the Secret

All application state is in PostgreSQL; point `DATABASE_URL` at one that is
backed up. The default pairs with a `cnpg-cluster` named `drop-db`.

```shell
kubectl create secret generic drop \
  --from-literal=DATABASE_URL='postgres://drop:…@drop-db-rw:5432/drop'
```

Prisma runs its migrations before the server listens, so the first boot against
a fresh database is slower than the ones after it — that is what the startup
probe's budget is for.

## `externalUrl` is what clients enrol against

The desktop client is handed `EXTERNAL_URL` and talks back to it. Behind an
exposure it must be the address a client on the outside can reach; the
in-cluster Service name will enrol clients against an address that does not
resolve for them.

## Ports

nginx inside the image listens on `:3000` and proxies the Nuxt server on `:4000`
and the torrential depot on `:5000`. Only `:3000` is worth exposing, and it is
the only port this workload declares.

## Less hardened, deliberately

nginx binds `:3000` and forks its workers to another account, which it can only
do starting from root, so this runs as root with privilege escalation allowed
and capabilities kept. The root filesystem is writable because nginx keeps its
pid, access log and temporary bodies in the working directory inside the image's
own tree, and Prisma writes its engines there too.

## Persistence

Two ReadWriteOnce volumes — the imported games and the object store — so this is
**one replica, recreated** (never rolled).

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
metadata: { name: kurly, namespace: drop }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-drop, namespace: drop }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/drop, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: drop }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-drop, namespace: drop }
spec: { sourceRef: { kind: OCIRepository, name: kurly-drop } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: drop, namespace: drop }
spec:
  serviceAccountName: drop-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/drop/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-drop, importPath: github.com/metio/kurly/workloads/drop }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: drop, namespace: drop }
spec:
  serviceAccountName: drop-deployer
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
        name: drop
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: drop }
```

<!-- END generated: jaas-deploy -->
