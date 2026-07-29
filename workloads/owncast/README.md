<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# owncast

[Owncast](https://owncast.online) — a self-hosted live video streaming and chat server,
an open alternative to Twitch: you stream to it over RTMP and viewers watch on your own
site. A plain composable `kurly.http` workload on the official image; its data (SQLite
config, chat history, stream segments) lives on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local owncast = import 'github.com/metio/kurly/workloads/owncast/server.libsonnet';
kurly.list(owncast())
```

Streaming **into** Owncast uses RTMP on `:1935`, a separate port this HTTP workload does
not expose — add a Service for it (a raw `+` patch or a dedicated LoadBalancer). The web
player works without it. Data at `/app/data` on a ReadWriteOnce volume, so **one replica,
recreated**. Serves the web player on `:8080`.

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
metadata: { name: kurly, namespace: owncast }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-owncast, namespace: owncast }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/owncast, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: owncast }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-owncast, namespace: owncast }
spec: { sourceRef: { kind: OCIRepository, name: kurly-owncast } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: owncast, namespace: owncast }
spec:
  serviceAccountName: owncast-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/owncast/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-owncast, importPath: github.com/metio/kurly/workloads/owncast }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: owncast, namespace: owncast }
spec:
  serviceAccountName: owncast-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: owncast
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: owncast }
```

<!-- END generated: jaas-deploy -->
