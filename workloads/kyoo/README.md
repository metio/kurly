<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# kyoo

[Kyoo](https://github.com/zoriya/kyoo) — a media browser and streaming server for
films and television. This workload carries Kyoo's **API**: a plain composable
`kurly.http` workload on the official image, backed by an external PostgreSQL, with
the artwork it downloads on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local kyoo = import 'github.com/metio/kurly/workloads/kyoo/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.list([
  cnpg(name='kyoo-db', database='kyoo'),
  kyoo(publicUrl='https://kyoo.example.com'),
])
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `kyoo` | |
| `image` | `ghcr.io/zoriya/kyoo_api:5.1.0` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | artwork (`/images`) |
| `publicUrl` | unset | the public URL, and the JWT issuer |
| `authServer` | `http://kyoo-auth:4568` | the Kyoo auth service whose JWKS verifies tokens |
| `dbHost` / `database` / `dbUser` | `kyoo-db-rw` / `kyoo` / `kyoo` | |
| `secretName` | `kyoo` | Secret with `PGPASSWORD` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves on `:3567` — compose an exposure onto it.

## Backends and secrets

The connection settings are plain parameters (`PGHOST`, `PGDATABASE`, `PGUSER`); the
password comes from `secretName` as `PGPASSWORD` via `envFrom`, and kurly authors
**no Secret** — fill it with [`kurly.externalSecret`](../../main.libsonnet) or from
your secret store. The defaults pair with a [cnpg-cluster](../cnpg-cluster/) named
`kyoo-db`. On first start the API creates its own `kyoo` schema and runs the
migrations, which is what the startup probe waits out; it also needs the `pg_trgm`
extension, which a stock PostgreSQL ships.

## The rest of Kyoo

Kyoo is several services. The API is the one carried here; the front end, the `auth`
service that issues the JWTs it verifies, and the transcoder are separate images with
separate concerns (the transcoder wants the media library and hardware acceleration).
Point `authServer` at wherever the auth service runs, and set `publicUrl` to the
issuer it stamps into its tokens — a mismatch makes every authenticated request fail.

## Persistence

Downloaded artwork lives on a ReadWriteOnce volume, so this is **one replica,
recreated**.

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
metadata: { name: kurly, namespace: kyoo }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-kyoo, namespace: kyoo }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/kyoo, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: kyoo }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-kyoo, namespace: kyoo }
spec: { sourceRef: { kind: OCIRepository, name: kurly-kyoo } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: kyoo, namespace: kyoo }
spec:
  serviceAccountName: kyoo-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/kyoo/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-kyoo, importPath: github.com/metio/kurly/workloads/kyoo }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: kyoo, namespace: kyoo }
spec:
  serviceAccountName: kyoo-deployer
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
        name: kyoo
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: kyoo }
```

<!-- END generated: jaas-deploy -->
