<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# microbin

[MicroBin](https://github.com/szabodanika/microbin) — a tiny, self-contained
pastebin and file-sharing service. A plain composable `kurly.http` workload that
keeps its pastes and uploaded files on a PersistentVolume, so it needs no external
database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local microbin = import 'github.com/metio/kurly/workloads/microbin/server.libsonnet';

kurly.list(microbin())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `microbin` | |
| `image` | `docker.io/danielszabo99/microbin:v2.1.4` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | pastes and files (`/app/microbin_data`) |
| `env` | `{}` | extra `MICROBIN_*` settings |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:8080` — compose an exposure onto it.

## Persistence

The pastes and files live on a ReadWriteOnce volume, so this is **one replica,
recreated** — the same single-writer discipline as [vaultwarden](../vaultwarden/).

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
metadata: { name: kurly, namespace: microbin }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-microbin, namespace: microbin }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/microbin, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: microbin }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-microbin, namespace: microbin }
spec: { sourceRef: { kind: OCIRepository, name: kurly-microbin } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: microbin, namespace: microbin }
spec:
  serviceAccountName: microbin-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/microbin/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-microbin, importPath: github.com/metio/kurly/workloads/microbin }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: microbin, namespace: microbin }
spec:
  serviceAccountName: microbin-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: microbin
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: microbin }
```

<!-- END generated: jaas-deploy -->
