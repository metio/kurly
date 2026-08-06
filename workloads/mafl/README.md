<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mafl

[Mafl](https://github.com/hywax/mafl) — a minimalistic, configurable homepage for
your services. A plain composable `kurly.http` workload on the official image; its
configuration lives on a PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mafl = import 'github.com/metio/kurly/workloads/mafl/server.libsonnet';

kurly.list(mafl())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `mafl` | |
| `image` | `ghcr.io/hywax/mafl:v0.15.4` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | configuration (`/app/data`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the homepage on `:3000` — compose an exposure onto it. Edit
`/app/data/config.yml` on the volume to configure it; the image seeds a default
there on first start.

## Security and persistence

The Nitro server writes nothing outside its data directory and `/tmp`, so the
hardened default posture stands whole: non-root, read-only root filesystem,
dropped capabilities, no privilege escalation. The configuration lives on a
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
metadata: { name: kurly, namespace: mafl }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-mafl, namespace: mafl }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/mafl, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: mafl }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-mafl, namespace: mafl }
spec: { sourceRef: { kind: OCIRepository, name: kurly-mafl } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: mafl, namespace: mafl }
spec:
  serviceAccountName: mafl-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/mafl/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-mafl, importPath: github.com/metio/kurly/workloads/mafl }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: mafl, namespace: mafl }
spec:
  serviceAccountName: mafl-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: mafl
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: mafl }
```

<!-- END generated: jaas-deploy -->
