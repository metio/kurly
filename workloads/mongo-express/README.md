<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mongo-express

[mongo-express](https://github.com/mongo-express/mongo-express) — a lightweight, web-based MongoDB admin UI. A **stateless** `kurly.http` workload on the official image.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mongoExpress = import 'github.com/metio/kurly/workloads/mongo-express/server.libsonnet';
kurly.list(mongoExpress())
```

`ME_CONFIG_MONGODB_URL` and the basic-auth credentials come from a Secret via `envFrom` — kurly authors **no Secret**. Serves on `:8081`.

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
metadata: { name: kurly, namespace: mongo-express }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-mongo-express, namespace: mongo-express }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/mongo-express, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: mongo-express }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-mongo-express, namespace: mongo-express }
spec: { sourceRef: { kind: OCIRepository, name: kurly-mongo-express } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: mongo-express, namespace: mongo-express }
spec:
  serviceAccountName: mongo-express-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/mongo-express/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-mongo-express, importPath: github.com/metio/kurly/workloads/mongo-express }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: mongo-express, namespace: mongo-express }
spec:
  serviceAccountName: mongo-express-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: mongo-express
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: mongo-express }
```

<!-- END generated: jaas-deploy -->
