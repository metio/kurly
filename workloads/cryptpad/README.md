<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# cryptpad

[CryptPad](https://cryptpad.org/) — end-to-end encrypted, collaborative documents,
spreadsheets, and more. A plain composable `kurly.http` workload on the official
image that keeps its encrypted blocks, blobs, and datastore on a PersistentVolume,
so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local cryptpad = import 'github.com/metio/kurly/workloads/cryptpad/server.libsonnet';

kurly.list(cryptpad())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `cryptpad` | |
| `image` | `docker.io/cryptpad/cryptpad:2026.5.1` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | the encrypted datastore (`/cryptpad/data`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the app on `:3000` — compose an exposure onto it.

## Configuration

CryptPad needs a `config.js` at `/cryptpad/config/config.js` setting
`httpUnsafeOrigin` (the main URL) and `httpSafeOrigin` (a **separate sandbox
domain** — required for its security model). Mount it with `kurly.config`; both
origins must resolve to this Service.

## Security and persistence

The Node app writes to several paths under `/cryptpad` at runtime, so this workload
relaxes kurly's read-only-rootfs default while keeping non-root, dropped
capabilities, and no privilege escalation. The encrypted datastore lives on a
ReadWriteOnce volume, so this is **one replica, recreated**.

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
metadata: { name: kurly, namespace: cryptpad }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-cryptpad, namespace: cryptpad }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/cryptpad, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: cryptpad }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-cryptpad, namespace: cryptpad }
spec: { sourceRef: { kind: OCIRepository, name: kurly-cryptpad } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: cryptpad, namespace: cryptpad }
spec:
  serviceAccountName: cryptpad-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/cryptpad/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-cryptpad, importPath: github.com/metio/kurly/workloads/cryptpad }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: cryptpad, namespace: cryptpad }
spec:
  serviceAccountName: cryptpad-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: cryptpad
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: cryptpad }
```

<!-- END generated: jaas-deploy -->
