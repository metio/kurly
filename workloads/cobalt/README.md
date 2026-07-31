<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# cobalt

[cobalt](https://github.com/imputnet/cobalt) — a self-hosted media-downloader backend: give it a link and it returns a clean download for supported sites. A `kurly.http` workload on the official image. The API is stateless — it streams and re-muxes on demand and keeps nothing.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local cobalt = import 'github.com/metio/kurly/workloads/cobalt/server.libsonnet';
kurly.list(cobalt(apiUrl='https://cobalt-api.example.com'))
```

Stateless — a plain, horizontally scalable Deployment. Serves the API on `:9000`. This is the API only; run a cobalt web frontend separately if you want the UI.

**Configuration:** cobalt reads `API_URL` (its own public URL, required) and optional tuning/auth settings from the environment. Provide any secret tokens through a Secret (compose `kurly.envFromSecret` on).

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
metadata: { name: kurly, namespace: cobalt }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-cobalt, namespace: cobalt }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/cobalt, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: cobalt }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-cobalt, namespace: cobalt }
spec: { sourceRef: { kind: OCIRepository, name: kurly-cobalt } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: cobalt, namespace: cobalt }
spec:
  serviceAccountName: cobalt-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/cobalt/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-cobalt, importPath: github.com/metio/kurly/workloads/cobalt }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: cobalt, namespace: cobalt }
spec:
  serviceAccountName: cobalt-deployer
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
        name: cobalt
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: cobalt }
```

<!-- END generated: jaas-deploy -->
