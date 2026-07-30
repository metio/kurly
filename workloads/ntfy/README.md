<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# ntfy

[ntfy](https://ntfy.sh/) — send push notifications to your phone or desktop over
simple HTTP. A plain composable `kurly.http` workload that keeps its message cache
and user database in SQLite on a PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local ntfy = import 'github.com/metio/kurly/workloads/ntfy/server.libsonnet';

kurly.list(ntfy(baseUrl='https://ntfy.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `ntfy` | |
| `image` | `docker.io/binwiederhier/ntfy:v2.26.3` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | cache, auth db, attachments (`/var/lib/ntfy`) |
| `baseUrl` | inferred | the public URL (needed for the web app, attachments, iOS) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app and publish/subscribe API on `:80` — compose an exposure onto it.

## Persistence

The SQLite cache and auth database live on a ReadWriteOnce volume, so this is **one
replica, recreated** — the same single-writer discipline as
[vaultwarden](../vaultwarden/).

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
metadata: { name: kurly, namespace: ntfy }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-ntfy, namespace: ntfy }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/ntfy, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: ntfy }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-ntfy, namespace: ntfy }
spec: { sourceRef: { kind: OCIRepository, name: kurly-ntfy } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: ntfy, namespace: ntfy }
spec:
  serviceAccountName: ntfy-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/ntfy/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-ntfy, importPath: github.com/metio/kurly/workloads/ntfy }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: ntfy, namespace: ntfy }
spec:
  serviceAccountName: ntfy-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: ntfy
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: ntfy }
```

<!-- END generated: jaas-deploy -->
