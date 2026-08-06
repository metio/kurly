<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# jotty

[jotty](https://github.com/fccview/jotty) — notes and checklists kept as plain
Markdown and JSON files, with no database anywhere. A plain composable
`kurly.http` workload; everything it owns lives on PersistentVolumes.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local jotty = import 'github.com/metio/kurly/workloads/jotty/server.libsonnet';

kurly.list(jotty())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `jotty` | |
| `image` | `ghcr.io/fccview/jotty:1.25.1` | |
| `storageSize` / `configSize` | `5Gi` / `1Gi` | `/app/data` and `/app/config` |
| `storageClass` | cluster default | both volumes |
| `appUrl` | absent | the public URL, when a proxy terminates TLS |
| `env` / `resources` / `labels` / `annotations` | | |

## Two volumes, because it writes in two places

`/app/data` holds the notes, checklists, users, sessions and encryption keys.
`/app/config` holds what an administrator customises from the settings page —
themes, emojis, custom CSS. The image ships defaults for the second and the
mount hides them; jotty falls back to an empty configuration for each, so a
fresh volume is a jotty with no customisation rather than a broken one.

Files on ReadWriteOnce volumes, so this is **one replica, recreated** (never
rolled). Two pods writing the same Markdown tree is not something anything here
reconciles afterwards.

## Behind a proxy

`appUrl` is absent by default. Relative links work until the instance is
exposed, and a wrong absolute base is worse than none — set it to the host
users actually reach, and jotty builds its links and cookie settings from it.

## Storage without a database

There is nothing external to provision: a volume is the whole dependency list.
That also means a backup of these two volumes is a backup of the instance —
compose `kurly.backup.*` onto it and both claims are covered.

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
metadata: { name: kurly, namespace: jotty }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-jotty, namespace: jotty }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/jotty, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: jotty }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-jotty, namespace: jotty }
spec: { sourceRef: { kind: OCIRepository, name: kurly-jotty } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: jotty, namespace: jotty }
spec:
  serviceAccountName: jotty-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/jotty/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-jotty, importPath: github.com/metio/kurly/workloads/jotty }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: jotty, namespace: jotty }
spec:
  serviceAccountName: jotty-deployer
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
        name: jotty
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: jotty }
```

<!-- END generated: jaas-deploy -->
