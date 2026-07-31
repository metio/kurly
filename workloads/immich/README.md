<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# immich

[Immich](https://immich.app) — a self-hosted, high-performance photo and video backup. It runs as
**two workloads** — the `server` (API + web app) and a `machine-learning` inference service —
backed by a PostgreSQL with the **VectorChord** extension (for smart search) and a Redis.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local server = import 'github.com/metio/kurly/workloads/immich/server.libsonnet';
local ml = import 'github.com/metio/kurly/workloads/immich/machine-learning.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
local valkey = import 'github.com/metio/kurly/workloads/valkey/instance.libsonnet';

kurly.list([
  cnpg(
    name='immich-db',
    database='immich',
    // Immich needs VectorChord — a CNPG-compatible image that ships it, plus the
    // preload of vchord.so (see PostgreSQL below).
    imageName='ghcr.io/tensorchord/cloudnative-vectorchord:16.9-0.4.3',
    parameters={ shared_preload_libraries: 'vchord.so' },
  ),
  valkey(name='immich-cache'),
  server(),
  ml(),
  // The Immich-shaped Secret the server reads (DB_PASSWORD); fill it from the
  // CNPG cluster's own immich-db-app Secret, or from your secret store.
  kurly.externalSecret('immich', { name: 'vault', kind: 'ClusterSecretStore' }, [
    { secretKey: 'DB_PASSWORD', remoteRef: { key: 'immich/db', property: 'password' } },
  ]),
])
```

The **server** serves the web app and API on `:2283`, storing the media library on a
ReadWriteOnce volume at `/data` — one replica, recreated (point `storageClass` at a ReadWriteMany
class to run several). The **machine-learning** stage serves inference on `:3003` and caches its
downloaded models on a volume at `/cache`; the server reaches it at `http://immich-machine-learning:3003`.

The non-secret connection settings (`DB_HOSTNAME`, `DB_DATABASE_NAME`, `DB_USERNAME`,
`REDIS_HOSTNAME`, `IMMICH_MACHINE_LEARNING_URL`) are parameters; the database password comes from
`secretName` (`immich-secrets`) as `DB_PASSWORD` — kurly authors **no Secret**. Compose an
exposure onto the server.

## PostgreSQL: the VectorChord extension

Immich's smart search needs the **`vchord`** (VectorChord) PostgreSQL extension, which is not part
of a stock PostgreSQL. Two things are required of whatever database you point Immich at:

- **An image that ships the extension.** The example pins the CNPG-compatible
  [`ghcr.io/tensorchord/cloudnative-vectorchord`](https://github.com/tensorchord/cloudnative-vectorchord)
  image via the cnpg-cluster `imageName` parameter. (A plain `ghcr.io/cloudnative-pg/postgresql`
  image does not carry `vchord`.)
- **`shared_preload_libraries` including `vchord.so`.** Passed through cnpg-cluster's `parameters`,
  which merges into the cluster's `postgresql.conf`.

Immich creates the extension itself during its startup migration when `DB_VECTOR_EXTENSION` is set
(this stage sets it to `vectorchord`). If your database role cannot `CREATE EXTENSION`, create it
once as a superuser (`CREATE EXTENSION IF NOT EXISTS vchord CASCADE;`) before Immich starts — on
CNPG, through the cluster's post-init SQL.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**e2e** — this workload is deployed to a live cluster by a smoke scenario and observed reaching readiness, on top of its test coverage.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stages with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
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
metadata: { name: kurly, namespace: immich }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-immich, namespace: immich }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/immich, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: immich }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-immich, namespace: immich }
spec: { sourceRef: { kind: OCIRepository, name: kurly-immich } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: immich-machine-learning, namespace: immich }
spec:
  serviceAccountName: immich-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local machine_learning = import 'github.com/metio/kurly/workloads/immich/machine-learning.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(machine_learning())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-immich, importPath: github.com/metio/kurly/workloads/immich }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: immich-server, namespace: immich }
spec:
  serviceAccountName: immich-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/immich/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-immich, importPath: github.com/metio/kurly/workloads/immich }
```

A `StageSet` deploys the stages in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: immich, namespace: immich }
spec:
  serviceAccountName: immich-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: machine-learning
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: immich-machine-learning
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: immich-machine-learning }
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: immich-server
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: immich-server }
```

<!-- END generated: jaas-deploy -->
