<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mazanoke

[MAZANOKE](https://github.com/civilblur/mazanoke) — a self-hosted, client-side image optimizer that compresses and converts images entirely in the browser. A `kurly.http` workload on the official image; all processing happens client-side, so the server only serves static assets and holds no data.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mazanoke = import 'github.com/metio/kurly/workloads/mazanoke/server.libsonnet';
kurly.list(mazanoke())
```

Stateless — a plain, horizontally scalable Deployment. Serves on `:80`. Images never leave the browser.

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
metadata: { name: kurly, namespace: mazanoke }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-mazanoke, namespace: mazanoke }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/mazanoke, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: mazanoke }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-mazanoke, namespace: mazanoke }
spec: { sourceRef: { kind: OCIRepository, name: kurly-mazanoke } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: mazanoke, namespace: mazanoke }
spec:
  serviceAccountName: mazanoke-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/mazanoke/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-mazanoke, importPath: github.com/metio/kurly/workloads/mazanoke }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: mazanoke, namespace: mazanoke }
spec:
  serviceAccountName: mazanoke-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: mazanoke
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: mazanoke }
```

<!-- END generated: jaas-deploy -->
