<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# ghostfolio

[Ghostfolio](https://ghostfol.io) — a self-hosted, open-source wealth-management and portfolio tracker for stocks, ETFs, crypto and more. A `kurly.http` workload on the official image, backed by an external PostgreSQL and Redis.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local ghostfolio = import 'github.com/metio/kurly/workloads/ghostfolio/server.libsonnet';
kurly.list(ghostfolio())
```

Stateless — a plain rolling Deployment. Serves on `:3333`.

**Secrets:** Ghostfolio reads `DATABASE_URL`, the Redis settings, `ACCESS_TOKEN_SALT` and `JWT_SECRET_KEY` from the environment. kurly authors no Secret; provide one (via `secretName`) holding them. The defaults pair with a `cnpg-cluster` named `ghostfolio-db` and a Redis.

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
metadata: { name: kurly, namespace: ghostfolio }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-ghostfolio, namespace: ghostfolio }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/ghostfolio, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: ghostfolio }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-ghostfolio, namespace: ghostfolio }
spec: { sourceRef: { kind: OCIRepository, name: kurly-ghostfolio } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: ghostfolio, namespace: ghostfolio }
spec:
  serviceAccountName: ghostfolio-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/ghostfolio/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-ghostfolio, importPath: github.com/metio/kurly/workloads/ghostfolio }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: ghostfolio, namespace: ghostfolio }
spec:
  serviceAccountName: ghostfolio-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: ghostfolio
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: ghostfolio }
```

<!-- END generated: jaas-deploy -->
