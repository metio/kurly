<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# quickshare

[Quickshare](https://github.com/ihexxa/quickshare) — simple file sharing between
devices: upload from one, browse from another, hand out a share link to someone
else. A plain composable `kurly.http` workload; the shared files and the SQLite
database indexing them live together on a PersistentVolume, so it needs nothing
external.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local quickshare = import 'github.com/metio/kurly/workloads/quickshare/server.libsonnet';

kurly.list(quickshare())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `quickshare` | |
| `image` | `hexxa/quickshare:v0.11.4` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | `/quickshare/root` |
| `secretName` | `quickshare` | `DEFAULTADMIN`, `DEFAULTADMINPWD` |
| `env` / `resources` / `labels` / `annotations` | | |

## The first administrator comes from the Secret

Quickshare creates its administrator on the **first start** and never again. The
Secret named by `secretName` supplies that account as `DEFAULTADMIN` and
`DEFAULTADMINPWD`; without them Quickshare invents a password and prints it to
the log once, which is not a credential anybody can rely on finding later. kurly
mints no Secret.

Changing either value afterwards does nothing — the account already exists, and
the password is changed from inside the application.

## Persistence

Both halves of the state are one volume: the uploaded files under
`/quickshare/root` and the SQLite database that indexes them beside them, the
layout the image's own `/quickshare/docker.yml` configures. That makes this
**one replica, recreated** (never rolled) — two pods writing one SQLite file and
one file tree is corruption, not capacity.

Size the volume for what people will actually upload; unlike a database workload,
the volume here *is* the product.

## Runs as 8686

The image group-owns its whole tree by uid/gid 8686 at mode 0770 but sets no
`USER`, so the workload pins that account and gives the volume the same `fsGroup`.
Everything else keeps the hardened default: non-root, no privilege escalation, all
capabilities dropped, read-only root filesystem with a scratch `/tmp`.

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
metadata: { name: kurly, namespace: quickshare }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-quickshare, namespace: quickshare }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/quickshare, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: quickshare }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-quickshare, namespace: quickshare }
spec: { sourceRef: { kind: OCIRepository, name: kurly-quickshare } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: quickshare, namespace: quickshare }
spec:
  serviceAccountName: quickshare-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/quickshare/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-quickshare, importPath: github.com/metio/kurly/workloads/quickshare }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: quickshare, namespace: quickshare }
spec:
  serviceAccountName: quickshare-deployer
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
        name: quickshare
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: quickshare }
```

<!-- END generated: jaas-deploy -->
