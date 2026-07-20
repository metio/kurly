<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# greenlight

[Greenlight 3](https://github.com/bigbluebutton/greenlight) — the official
[BigBlueButton](https://bigbluebutton.org/) front-end: a Rails app for scheduling and
joining BBB rooms and meetings. A plain composable `kurly.http` workload on the
official image, backed by an external PostgreSQL and Redis. It reaches an existing
BigBlueButton server over the network — kurly does not run BBB itself.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local greenlight = import 'github.com/metio/kurly/workloads/greenlight/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(cnpg(name='greenlight-db', database='greenlight')).items,
  kurly.list(greenlight()).items,
]))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `greenlight` | |
| `image` | `docker.io/bigbluebutton/greenlight:v3.8.2.3` | |
| `replicas` | `2` | stateless — scale freely |
| `secretName` | `greenlight-secrets` | `DATABASE_URL`, `REDIS_URL`, `SECRET_KEY_BASE`, `BIGBLUEBUTTON_ENDPOINT`, `BIGBLUEBUTTON_SECRET` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app on `:3000` — compose an exposure onto it.

## Backends and secrets

Greenlight reads `DATABASE_URL`, `REDIS_URL`, `SECRET_KEY_BASE` and the BigBlueButton
endpoint/secret (`BIGBLUEBUTTON_ENDPOINT`, `BIGBLUEBUTTON_SECRET`) from the
environment. kurly authors **no Secret** — provide `greenlight-secrets` holding them,
pulled in via `envFrom` (fill it with [`kurly.externalSecret`](../../main.libsonnet)).
The defaults pair with a [cnpg-cluster](../cnpg-cluster/) named `greenlight-db` and a
Redis.

## Persistence

Recordings and presentations live on the BigBlueButton server, not here, so this is
**stateless** — a plain rolling Deployment with no volume.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**rendered** — this workload renders and validates against the Kubernetes schemas with its defaults.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stage with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
are single-layer, so a plain Flux `OCIRepository` pulls each one directly.

```yaml
# The kurly library (recipes) and this workload (source), both single-layer
# images from their release pipelines, pulled by plain OCIRepositories.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: greenlight }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-greenlight, namespace: greenlight }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/greenlight, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: greenlight }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-greenlight, namespace: greenlight }
spec: { sourceRef: { kind: OCIRepository, name: kurly-greenlight } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: greenlight, namespace: greenlight }
spec:
  serviceAccountName: greenlight-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/greenlight/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-greenlight, importPath: github.com/metio/kurly/workloads/greenlight }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: greenlight, namespace: greenlight }
spec:
  serviceAccountName: greenlight-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: greenlight
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: greenlight }
```

<!-- END generated: jaas-deploy -->
