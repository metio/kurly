<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# nats

[NATS](https://nats.io) — a fast, lightweight, self-hosted messaging system for cloud-native apps: pub/sub, request/reply and, with JetStream, persistent streams. NATS speaks its own protocol on `:4222`, with its JetStream store on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local nats = import 'github.com/metio/kurly/workloads/nats/server.libsonnet';
kurly.list(nats())
```

JetStream is enabled with its store on the volume. Single server (a real deployment runs a NATS cluster). The monitoring endpoint (`:8222`) needs an extra Service. Data at `/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves clients on `:4222`.

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
metadata: { name: kurly, namespace: nats }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-nats, namespace: nats }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/nats, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: nats }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-nats, namespace: nats }
spec: { sourceRef: { kind: OCIRepository, name: kurly-nats } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: nats, namespace: nats }
spec:
  serviceAccountName: nats-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/nats/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-nats, importPath: github.com/metio/kurly/workloads/nats }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: nats, namespace: nats }
spec:
  serviceAccountName: nats-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: nats
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: nats }
```

<!-- END generated: jaas-deploy -->
