<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# kresus

[Kresus](https://kresus.org/) — a personal finance manager that aggregates bank
accounts through [woob](https://woob.tech/), categorises what arrives and budgets
against it. A composable `kurly.http` workload backed by an **external
PostgreSQL**; woob's downloaded bank modules and Kresus' own data directory live
on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local kresus = import 'github.com/metio/kurly/workloads/kresus/server.libsonnet';

kurly.list(kresus())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `kresus` | |
| `image` | `bnjbvr/kresus:0.25.4` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | `/home/user/data` |
| `dbHost` / `dbPort` / `database` / `dbUser` | `kresus-db-rw` / `5432` / `kresus` / `kresus` | |
| `secretName` | `kresus` | `KRESUS_DB_PASSWORD`, `KRESUS_SALT` |
| `env` / `resources` / `labels` / `annotations` | | |

## PostgreSQL, not SQLite

Kresus can use SQLite and upstream discourages it outright: it cannot carry the
migrations across an upgrade. The cheap default is the one that strands the data
on the next release, so this stage speaks PostgreSQL and needs one — the
`cnpg-cluster` workload provides it.

`KRESUS_SALT` encrypts exports. It is not a value to regenerate: an export taken
under one salt cannot be read back under another.

## It reaches the internet every time it starts

The image's entrypoint `pip install`s the latest woob on every start and exits
the container when that fails, so a cluster with no egress to PyPI cannot start
this pod. The same entrypoint would also `yarn global upgrade kresus` past the
pinned tag; that half is switched off here (`IS_NIGHTLY=1`) so what runs is what
the image says it is.

Because the install and the first migration are minutes rather than seconds, the
budget is in a startup probe, not in a longer liveness delay.

## Less hardened, deliberately

The entrypoint renumbers its `user` account, writes a git identity, installs
woob, chowns the home directory and only then drops privileges with `su` — all
of which starts from root, with a writable root filesystem.

## Persistence

One data directory on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled).

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
metadata: { name: kurly, namespace: kresus }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-kresus, namespace: kresus }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/kresus, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: kresus }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-kresus, namespace: kresus }
spec: { sourceRef: { kind: OCIRepository, name: kurly-kresus } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: kresus, namespace: kresus }
spec:
  serviceAccountName: kresus-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/kresus/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-kresus, importPath: github.com/metio/kurly/workloads/kresus }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: kresus, namespace: kresus }
spec:
  serviceAccountName: kresus-deployer
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
        name: kresus
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: kresus }
```

<!-- END generated: jaas-deploy -->
