<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# atsumeru

[Atsumeru](https://github.com/Atsumeru-xyz/Atsumeru) — a media server for manga,
comics and light novels, read with native desktop and Android clients. A plain
composable `kurly.http` workload on the official image: it keeps its
configuration, database, cover cache and logs on a PersistentVolume and reads its
library from the same volume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local atsumeru = import 'github.com/metio/kurly/workloads/atsumeru/server.libsonnet';

kurly.list(atsumeru())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `atsumeru` | |
| `image` | `docker.io/atsumerudev/atsumeru:1.1` | |
| `storageSize` / `storageClass` | `50Gi` / cluster default | configuration (`/app/config`), database, cache, logs and library (`/library`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the web UI and the REST API on `:31337` — compose an exposure onto it. Put
your manga and comic archives under `/library` on the volume.

The admin password is **printed to the log on the first start** and stored nowhere
else, so read the pod's log after the first rollout.

## Security and persistence

The JVM writes temp files to the root filesystem, so this workload relaxes kurly's
read-only-rootfs default while keeping non-root, dropped capabilities, and no
privilege escalation. Probes are connection probes: the server answers
`/api/server/ping` with a 4xx while it is up and unauthenticated — its own
container healthcheck greps for exactly that — which an HTTP probe would read as a
failure and restart the pod forever. The database lives on a ReadWriteOnce volume,
so this is **one replica, recreated**.

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
metadata: { name: kurly, namespace: atsumeru }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-atsumeru, namespace: atsumeru }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/atsumeru, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: atsumeru }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-atsumeru, namespace: atsumeru }
spec: { sourceRef: { kind: OCIRepository, name: kurly-atsumeru } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: atsumeru, namespace: atsumeru }
spec:
  serviceAccountName: atsumeru-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/atsumeru/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-atsumeru, importPath: github.com/metio/kurly/workloads/atsumeru }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: atsumeru, namespace: atsumeru }
spec:
  serviceAccountName: atsumeru-deployer
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
        name: atsumeru
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: atsumeru }
```

<!-- END generated: jaas-deploy -->
