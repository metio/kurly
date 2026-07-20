<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# maloja

[Maloja](https://github.com/krateng/maloja) — a self-hosted music scrobble database and listening-statistics server, a self-hosted alternative to Last.fm. A `kurly.http` workload on the official image; database (SQLite) and configuration on a PersistentVolume under `/mljdata`.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local maloja = import 'github.com/metio/kurly/workloads/maloja/server.libsonnet';
kurly.list(maloja())
```

Data at `/mljdata` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:42010`.

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
metadata: { name: kurly, namespace: maloja }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-maloja, namespace: maloja }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/maloja, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: maloja }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-maloja, namespace: maloja }
spec: { sourceRef: { kind: OCIRepository, name: kurly-maloja } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: maloja, namespace: maloja }
spec:
  serviceAccountName: maloja-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/maloja/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-maloja, importPath: github.com/metio/kurly/workloads/maloja }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: maloja, namespace: maloja }
spec:
  serviceAccountName: maloja-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: maloja
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: maloja }
```

<!-- END generated: jaas-deploy -->
