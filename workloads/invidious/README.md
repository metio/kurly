<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# invidious

[Invidious](https://github.com/iv-org/invidious) — a privacy-preserving alternative
front end for YouTube. A plain composable `kurly.http` workload on the official
image, backed by an external PostgreSQL. It keeps no state of its own, so it claims
no volume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local invidious = import 'github.com/metio/kurly/workloads/invidious/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.list([
  cnpg(name='invidious-db', database='invidious'),
  invidious(domain='watch.example.com', externalPort=443),
])
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `invidious` | |
| `image` | `quay.io/invidious/invidious:latest` | |
| `domain` | none | the public domain the pages link to |
| `externalPort` | none | the port the public URLs carry — `443` behind TLS |
| `checkTables` | `true` | create and migrate the schema on start |
| `secretName` | `invidious` | Secret with `INVIDIOUS_DATABASE_URL`, `INVIDIOUS_HMAC_KEY` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:3000` — compose an exposure onto it.

## Configuration and secrets

The image ships `config/config.yml` and overrides every key from an
`INVIDIOUS_<KEY>` environment variable, so the whole configuration is environment:
no ConfigMap, and no configuration document anybody has to author. kurly authors
**no Secret** — provide `invidious` holding `INVIDIOUS_DATABASE_URL` and
`INVIDIOUS_HMAC_KEY`, pulled in via `envFrom`. The default pairs with a
[cnpg-cluster](../cnpg-cluster/) named `invidious-db`.

`checkTables` lets the server create and migrate its own schema on first start,
which is what makes a fresh database usable without a separate migration job — and
why the startup probe allows several minutes before the liveness probe takes over.

Service links are disabled deliberately: a Service named `invidious` makes
Kubernetes inject `INVIDIOUS_PORT` as a `tcp://` URL, which is exactly the name
Invidious reads as its listen port, and the server then fails to bind.

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
metadata: { name: kurly, namespace: invidious }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-invidious, namespace: invidious }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/invidious, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: invidious }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-invidious, namespace: invidious }
spec: { sourceRef: { kind: OCIRepository, name: kurly-invidious } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: invidious, namespace: invidious }
spec:
  serviceAccountName: invidious-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/invidious/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-invidious, importPath: github.com/metio/kurly/workloads/invidious }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: invidious, namespace: invidious }
spec:
  serviceAccountName: invidious-deployer
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
        name: invidious
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: invidious }
```

<!-- END generated: jaas-deploy -->
