<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# matrix-conduit

[Conduit](https://conduit.rs) — a lightweight, self-hosted Matrix homeserver written in Rust. A `kurly.http` workload on the official image; its embedded database on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local conduit = import 'github.com/metio/kurly/workloads/matrix-conduit/server.libsonnet';
kurly.list(conduit(serverName='matrix.example.com'))
```

The `serverName` is **baked into every user and room id at first start and cannot be changed** — set it deliberately, and make it reachable per the Matrix well-known/SRV rules. Data at `/var/lib/matrix-conduit` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:6167`.

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
metadata: { name: kurly, namespace: matrix-conduit }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-matrix-conduit, namespace: matrix-conduit }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/matrix-conduit, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: matrix-conduit }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-matrix-conduit, namespace: matrix-conduit }
spec: { sourceRef: { kind: OCIRepository, name: kurly-matrix-conduit } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: matrix-conduit, namespace: matrix-conduit }
spec:
  serviceAccountName: matrix-conduit-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/matrix-conduit/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-matrix-conduit, importPath: github.com/metio/kurly/workloads/matrix-conduit }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: matrix-conduit, namespace: matrix-conduit }
spec:
  serviceAccountName: matrix-conduit-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: matrix-conduit
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: matrix-conduit }
```

<!-- END generated: jaas-deploy -->
