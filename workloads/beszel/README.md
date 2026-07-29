<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# beszel

[Beszel](https://github.com/henrygd/beszel) — a lightweight server-monitoring
dashboard. This workload is the **hub**: a plain composable `kurly.http` workload
that keeps its data in SQLite on a PersistentVolume, so it needs no external
database. Beszel agents run on the machines you monitor and report to this hub.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local beszel = import 'github.com/metio/kurly/workloads/beszel/server.libsonnet';

kurly.list(beszel())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `beszel` | |
| `image` | `ghcr.io/henrygd/beszel/beszel:0.18.7` | the hub image |
| `storageSize` / `storageClass` | `1Gi` / cluster default | the SQLite data volume (`/beszel_data`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:8090` — compose an exposure onto it.

## Persistence

One SQLite database on a ReadWriteOnce volume, so this is **one replica, recreated**
— the same single-writer discipline as [vaultwarden](../vaultwarden/).

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
metadata: { name: kurly, namespace: beszel }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-beszel, namespace: beszel }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/beszel, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: beszel }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-beszel, namespace: beszel }
spec: { sourceRef: { kind: OCIRepository, name: kurly-beszel } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: beszel, namespace: beszel }
spec:
  serviceAccountName: beszel-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/beszel/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-beszel, importPath: github.com/metio/kurly/workloads/beszel }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: beszel, namespace: beszel }
spec:
  serviceAccountName: beszel-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: beszel
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: beszel }
```

<!-- END generated: jaas-deploy -->
