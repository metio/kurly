<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# tachidesk

[Suwayomi-Server](https://github.com/Suwayomi/Suwayomi-Server) (formerly Tachidesk) — a self-hosted manga reader and library server. A `kurly.http` workload on the official image; library and settings on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local tachidesk = import 'github.com/metio/kurly/workloads/tachidesk/server.libsonnet';
kurly.list(tachidesk())
```

Data on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:4567`.

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
metadata: { name: kurly, namespace: tachidesk }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-tachidesk, namespace: tachidesk }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/tachidesk, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: tachidesk }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-tachidesk, namespace: tachidesk }
spec: { sourceRef: { kind: OCIRepository, name: kurly-tachidesk } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: tachidesk, namespace: tachidesk }
spec:
  serviceAccountName: tachidesk-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/tachidesk/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-tachidesk, importPath: github.com/metio/kurly/workloads/tachidesk }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: tachidesk, namespace: tachidesk }
spec:
  serviceAccountName: tachidesk-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: tachidesk
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: tachidesk }
```

<!-- END generated: jaas-deploy -->
