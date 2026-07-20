<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# element-web

[Element Web](https://github.com/element-hq/element-web) — the popular self-hosted web client for the Matrix network. A **stateless** `kurly.http` workload on the official image; its `config.json` is mounted into the web root via a **subPath** ConfigMap mount, beside the app's own files.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local element = import 'github.com/metio/kurly/workloads/element-web/server.libsonnet';
kurly.list(element(homeserverUrl='https://matrix.example.com', serverName='example.com'))
```

Element is a client only — point it at a Matrix homeserver (e.g. [matrix-conduit](../matrix-conduit/)) via `homeserverUrl`/`serverName`. Pass `config` to override or extend Element's `config.json` verbatim. Serves on `:80`.

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
metadata: { name: kurly, namespace: element-web }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-element-web, namespace: element-web }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/element-web, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: element-web }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-element-web, namespace: element-web }
spec: { sourceRef: { kind: OCIRepository, name: kurly-element-web } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: element-web, namespace: element-web }
spec:
  serviceAccountName: element-web-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/element-web/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-element-web, importPath: github.com/metio/kurly/workloads/element-web }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: element-web, namespace: element-web }
spec:
  serviceAccountName: element-web-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: element-web
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: element-web }
```

<!-- END generated: jaas-deploy -->
