<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# synapse

[Synapse](https://github.com/element-hq/synapse) — the reference Matrix homeserver from the Matrix.org Foundation. A `kurly.http` workload on the official image; config, signing keys and (with the default SQLite backend) database on a PersistentVolume, generated on first start.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local synapse = import 'github.com/metio/kurly/workloads/synapse/server.libsonnet';
kurly.list(synapse(serverName='matrix.example.com'))
```

The `serverName` is **baked into every id and cannot be changed** — set it deliberately. Beyond a small instance, edit the generated `homeserver.yaml` on the volume to point at an external PostgreSQL. Data at `/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8008`.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**e2e** — this workload is deployed to a live cluster by a smoke scenario and observed reaching readiness, on top of its test coverage.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stage with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
are single-layer, so a plain Flux `OCIRepository` pulls each one directly.

```yaml
# The kurly library (recipes) and this workload (source), both single-layer
# images from their release pipelines, pulled by plain OCIRepositories.
#
# Pinned by VERSION, not by `latest`: a moveable tag means the source you
# render can change under you between reconciles, and there is no saying
# afterwards which one produced what is running. Renovate keeps these
# current, and can pin the digest on top if reproducibility has to survive a
# retagged registry. The catalog names the version each release published.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: synapse }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-synapse, namespace: synapse }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/synapse, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: synapse }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-synapse, namespace: synapse }
spec: { sourceRef: { kind: OCIRepository, name: kurly-synapse } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: synapse, namespace: synapse }
spec:
  serviceAccountName: synapse-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/synapse/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-synapse, importPath: github.com/metio/kurly/workloads/synapse }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: synapse, namespace: synapse }
spec:
  serviceAccountName: synapse-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: synapse
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: synapse }
```

<!-- END generated: jaas-deploy -->
