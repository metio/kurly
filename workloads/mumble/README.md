<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mumble

[Mumble](https://www.mumble.info) (Murmur) — a self-hosted, low-latency voice-chat server for gaming and communities. Mumble speaks its own voice protocol, not HTTP: it listens on `:64738` (TCP control, UDP voice), with its SQLite database on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mumble = import 'github.com/metio/kurly/workloads/mumble/server.libsonnet';
kurly.list(mumble())
```

The Service publishes the **TCP** control port; add a second Service for **UDP** voice (usually a LoadBalancer) — expose it to clients rather than an HTTP ingress. `MUMBLE_SUPERUSER_PASSWORD` comes from a Secret via `envFrom` — kurly authors **no Secret**. Data at `/data` on a ReadWriteOnce volume, so **one replica, recreated**.

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
metadata: { name: kurly, namespace: mumble }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-mumble, namespace: mumble }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/mumble, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: mumble }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-mumble, namespace: mumble }
spec: { sourceRef: { kind: OCIRepository, name: kurly-mumble } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: mumble, namespace: mumble }
spec:
  serviceAccountName: mumble-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/mumble/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-mumble, importPath: github.com/metio/kurly/workloads/mumble }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: mumble, namespace: mumble }
spec:
  serviceAccountName: mumble-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: mumble
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: mumble }
```

<!-- END generated: jaas-deploy -->
