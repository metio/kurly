<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# pingvin-share

[Pingvin Share](https://github.com/stonith404/pingvin-share) — a self-hosted, open-source file-sharing platform, an alternative to WeTransfer. A `kurly.http` workload on the official all-in-one image; SQLite database and uploaded shares on a PersistentVolume under `/opt/app/backend/data`.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local pingvin = import 'github.com/metio/kurly/workloads/pingvin-share/server.libsonnet';
kurly.list(pingvin())
```

Data at `/opt/app/backend/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:3000`.

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
metadata: { name: kurly, namespace: pingvin-share }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-pingvin-share, namespace: pingvin-share }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/pingvin-share, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: pingvin-share }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-pingvin-share, namespace: pingvin-share }
spec: { sourceRef: { kind: OCIRepository, name: kurly-pingvin-share } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: pingvin-share, namespace: pingvin-share }
spec:
  serviceAccountName: pingvin-share-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/pingvin-share/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-pingvin-share, importPath: github.com/metio/kurly/workloads/pingvin-share }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: pingvin-share, namespace: pingvin-share }
spec:
  serviceAccountName: pingvin-share-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: pingvin-share
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: pingvin-share }
```

<!-- END generated: jaas-deploy -->
