<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# tika

[Apache Tika](https://tika.apache.org) — a content-analysis toolkit that detects and extracts text and metadata from over a thousand file types. A **stateless** `kurly.http` workload on the official image. The text-extraction companion apps like [paperless-ngx](../paperless-ngx/) expect.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local tika = import 'github.com/metio/kurly/workloads/tika/server.libsonnet';
kurly.list(tika())
```

Serves on `:9998`.

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
metadata: { name: kurly, namespace: tika }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-tika, namespace: tika }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/tika, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: tika }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-tika, namespace: tika }
spec: { sourceRef: { kind: OCIRepository, name: kurly-tika } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: tika, namespace: tika }
spec:
  serviceAccountName: tika-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/tika/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-tika, importPath: github.com/metio/kurly/workloads/tika }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: tika, namespace: tika }
spec:
  serviceAccountName: tika-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: tika
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: tika }
```

<!-- END generated: jaas-deploy -->
