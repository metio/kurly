<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# it-tools

[IT-Tools](https://github.com/CorentinTh/it-tools) — a large collection of handy online
tools for developers and sysadmins (encoders, converters, generators, formatters), all
client-side. A plain composable `kurly.http` workload on the official image; it serves a
static app and keeps no state, so it is a plain **stateless** Deployment.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local itTools = import 'github.com/metio/kurly/workloads/it-tools/server.libsonnet';
kurly.list(itTools())
```

Serves on `:80`.

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
metadata: { name: kurly, namespace: it-tools }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-it-tools, namespace: it-tools }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/it-tools, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: it-tools }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-it-tools, namespace: it-tools }
spec: { sourceRef: { kind: OCIRepository, name: kurly-it-tools } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: it-tools, namespace: it-tools }
spec:
  serviceAccountName: it-tools-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/it-tools/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-it-tools, importPath: github.com/metio/kurly/workloads/it-tools }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: it-tools, namespace: it-tools }
spec:
  serviceAccountName: it-tools-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: it-tools
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: it-tools }
```

<!-- END generated: jaas-deploy -->
