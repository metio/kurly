<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# otterwiki

[An Otter Wiki](https://github.com/redimp/otterwiki) — a small wiki written in
Markdown, where every page is a file in a git repository and every edit is a
commit. A plain composable `kurly.http` workload; the repository and its index
live on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local otterwiki = import 'github.com/metio/kurly/workloads/otterwiki/server.libsonnet';

kurly.list(otterwiki())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `otterwiki` | |
| `image` | `redimp/otterwiki:2.9.4` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | `/app-data` |
| `env` / `resources` / `labels` / `annotations` | | |

## Set the permissions before you publish it

Otter Wiki starts **publicly readable and writable**, and the **first account
registered becomes the administrator**. On an instance reachable from the internet
that means both go to whoever arrives first.

Configure anonymous access and registration from the wiki's own settings page
before exposing it, or put an authenticating proxy in front. There is nothing in
this workload that can decide it for you.

## Less hardened, deliberately

`supervisord` runs nginx and the application together and drops privileges to
their accounts, which it can only do starting from root. It also binds `:80`.
The root filesystem is writable because nginx and supervisord keep their pid,
logs and temporary bodies inside the image's own tree.

## Persistence

One git repository on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled). That is stricter than it looks: two pods committing to
the same repository is not something git will sort out afterwards.

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
metadata: { name: kurly, namespace: otterwiki }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-otterwiki, namespace: otterwiki }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/otterwiki, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: otterwiki }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-otterwiki, namespace: otterwiki }
spec: { sourceRef: { kind: OCIRepository, name: kurly-otterwiki } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: otterwiki, namespace: otterwiki }
spec:
  serviceAccountName: otterwiki-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/otterwiki/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-otterwiki, importPath: github.com/metio/kurly/workloads/otterwiki }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: otterwiki, namespace: otterwiki }
spec:
  serviceAccountName: otterwiki-deployer
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
        name: otterwiki
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: otterwiki }
```

<!-- END generated: jaas-deploy -->
