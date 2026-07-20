<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# tandoor

[Tandoor Recipes](https://tandoor.dev) — a self-hosted recipe manager and meal planner with a smart shopping list. A `kurly.http` workload on the official image, backed by an external PostgreSQL; uploaded media on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local tandoor = import 'github.com/metio/kurly/workloads/tandoor/server.libsonnet';
kurly.list(tandoor())
```

Media at `/opt/recipes/mediafiles` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8080`.

**Secrets:** Tandoor reads `SECRET_KEY` and its PostgreSQL settings from the environment. kurly authors no Secret; provide one (via `secretName`) holding them. The defaults pair with a `cnpg-cluster` named `tandoor-db`.

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
metadata: { name: kurly, namespace: tandoor }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-tandoor, namespace: tandoor }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/tandoor, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: tandoor }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-tandoor, namespace: tandoor }
spec: { sourceRef: { kind: OCIRepository, name: kurly-tandoor } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: tandoor, namespace: tandoor }
spec:
  serviceAccountName: tandoor-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/tandoor/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-tandoor, importPath: github.com/metio/kurly/workloads/tandoor }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: tandoor, namespace: tandoor }
spec:
  serviceAccountName: tandoor-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: tandoor
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: tandoor }
```

<!-- END generated: jaas-deploy -->
