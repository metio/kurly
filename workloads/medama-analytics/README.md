<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# medama-analytics

[Medama](https://github.com/medama-io/medama) — privacy-first website analytics:
a tracker under a kilobyte that sets no cookie and keeps no IP address, with a
dashboard over the results. A plain composable `kurly.http` workload keeping both
of its embedded databases — a SQLite application database and a DuckDB analytics
database — on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local medama = import 'github.com/metio/kurly/workloads/medama-analytics/server.libsonnet';

kurly.list(medama())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `medama-analytics` | |
| `image` | `ghcr.io/medama-io/medama:v0.6.1` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | `/app/data` |
| `corsAllowedOrigins` | none | for a dashboard hosted elsewhere |
| `env` / `resources` / `labels` / `annotations` | | |

## The first account is already there

The first boot seeds one account, `admin`, with the password
`CHANGE_ME_ON_FIRST_LOGIN`. There is no Secret to mint and no setup wizard to
race — whoever reaches the dashboard first owns the instance, so log in and
change the password as soon as the pod is ready, before the exposure is public.

## The exposure has to be public

The tracker script is loaded by the browsers visiting the sites being measured,
and it posts events back to this server. Unlike most workloads here, keeping it
in-cluster does not merely make it inconvenient — it collects nothing at all.

## Certificates are the ingress controller's job

Medama can obtain its own certificates with `AUTO_SSL`, which makes the process
bind `:80` and `:443` directly. That is not wired here: compose an exposure and
let the cluster terminate TLS.

## Persistence

Two embedded databases, SQLite for the application and DuckDB for the analytics,
on one ReadWriteOnce volume — so this is **one replica, recreated** (never
rolled). `HOME` points at that volume as well, because DuckDB resolves its
extension directory under `$HOME` and the root filesystem is read-only.

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
metadata: { name: kurly, namespace: medama-analytics }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-medama-analytics, namespace: medama-analytics }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/medama-analytics, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: medama-analytics }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-medama-analytics, namespace: medama-analytics }
spec: { sourceRef: { kind: OCIRepository, name: kurly-medama-analytics } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: medama-analytics, namespace: medama-analytics }
spec:
  serviceAccountName: medama-analytics-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/medama-analytics/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-medama-analytics, importPath: github.com/metio/kurly/workloads/medama-analytics }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: medama-analytics, namespace: medama-analytics }
spec:
  serviceAccountName: medama-analytics-deployer
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
        name: medama-analytics
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: medama-analytics }
```

<!-- END generated: jaas-deploy -->
