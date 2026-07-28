<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# rss-bridge

[RSS-Bridge](https://github.com/RSS-Bridge/rss-bridge) — generates RSS/Atom feeds for
sites that do not publish their own, from a large library of community "bridges". A plain
composable `kurly.http` workload on the official image. It holds no persistent state —
feeds are produced on request — so it is a plain **stateless** Deployment.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local rssBridge = import 'github.com/metio/kurly/workloads/rss-bridge/server.libsonnet';
kurly.list(rssBridge())
```

To restrict which bridges are enabled, mount a `whitelist.txt` over `/app/whitelist.txt`.
Serves on `:80`.

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
metadata: { name: kurly, namespace: rss-bridge }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-rss-bridge, namespace: rss-bridge }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/rss-bridge, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: rss-bridge }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-rss-bridge, namespace: rss-bridge }
spec: { sourceRef: { kind: OCIRepository, name: kurly-rss-bridge } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: rss-bridge, namespace: rss-bridge }
spec:
  serviceAccountName: rss-bridge-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/rss-bridge/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-rss-bridge, importPath: github.com/metio/kurly/workloads/rss-bridge }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: rss-bridge, namespace: rss-bridge }
spec:
  serviceAccountName: rss-bridge-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: rss-bridge
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: rss-bridge }
```

<!-- END generated: jaas-deploy -->
