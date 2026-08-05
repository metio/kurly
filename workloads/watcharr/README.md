<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# watcharr

[Watcharr](https://github.com/sbondCo/Watcharr) — a watchlist for films and
television: what you have seen, what you are part-way through, and what you mean
to watch, with ratings and progress. A plain composable `kurly.http` workload
keeping its SQLite database on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local watcharr = import 'github.com/metio/kurly/workloads/watcharr/server.libsonnet';

kurly.list(watcharr())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `watcharr` | |
| `image` | `ghcr.io/sbondco/watcharr:v4.2.1` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | `/data` |
| `secretName` | `watcharr` | supplies `JWT_SECRET` |
| `env` / `resources` / `labels` / `annotations` | | |

## It needs egress, which is easy to forget

Watcharr looks film and series metadata up from TMDB **at runtime**. Nothing else
about this workload reaches outside the cluster, so a NetworkPolicy written from
the shape of the manifest will happily block it — and the failure is quiet: the
app runs, the UI loads, and searching simply returns nothing.

```jsonnet
watcharr() + kurly.network.kubernetes(allowTo=[{ cidr: '0.0.0.0/0', ports: [443] }])
```

## The Secret

`JWT_SECRET` signs the tokens users hold. Watcharr generates one into its data
directory when unset — which survives a restart here, because that directory is
the volume, but not a move to a fresh one. Supplying it makes sessions outlive the
volume:

```shell
kubectl create secret generic watcharr \
  --from-literal=JWT_SECRET="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
```

## Persistence

One SQLite database on a ReadWriteOnce volume, so this is **one replica,
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
metadata: { name: kurly, namespace: watcharr }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-watcharr, namespace: watcharr }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/watcharr, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: watcharr }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-watcharr, namespace: watcharr }
spec: { sourceRef: { kind: OCIRepository, name: kurly-watcharr } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: watcharr, namespace: watcharr }
spec:
  serviceAccountName: watcharr-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/watcharr/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-watcharr, importPath: github.com/metio/kurly/workloads/watcharr }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: watcharr, namespace: watcharr }
spec:
  serviceAccountName: watcharr-deployer
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
        name: watcharr
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: watcharr }
```

<!-- END generated: jaas-deploy -->
