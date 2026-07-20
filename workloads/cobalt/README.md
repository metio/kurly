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
metadata: { name: kurly, namespace: cobalt }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-cobalt, namespace: cobalt }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/cobalt, ref: { tag: latest } }
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
