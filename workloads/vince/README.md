<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# vince

[Vince](https://github.com/vinceanalytics/vince) — privacy-friendly web
analytics: a small script on a site posts events here, and a dashboard reports
them, without cookies and without following anybody between sites. A plain
composable `kurly.http` workload: one static Go binary with an embedded Pebble
database on a PersistentVolume, needing no database, cache or object storage
beside it.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local vince = import 'github.com/metio/kurly/workloads/vince/server.libsonnet';

kurly.list(vince(url='https://analytics.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `vince` | |
| `image` | `ghcr.io/vinceanalytics/vince:v1.11.8` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | `/data`, the event database |
| `url` | `http://localhost:8080` | the address browsers reach this instance at |
| `domains` | `[]` | sites created on startup |
| `secretName` | `vince` | supplies `VINCE_ADMIN_NAME`, `VINCE_ADMIN_PASSWORD` |
| `env` / `resources` / `labels` / `annotations` | | |

## `url` has no default that is right anywhere

The tracking snippet the dashboard hands out is built from `url`, so leaving it
at the placeholder produces a snippet that posts events nowhere — and nothing
fails: the pod is healthy, the dashboard loads, and no event ever arrives. Set it
to the host the exposure in front of this serves.

## The Secret is how anybody logs in

A self-hosted Vince has no sign-up. It creates the administrator account on
startup from `VINCE_ADMIN_NAME` and `VINCE_ADMIN_PASSWORD` when both are set; with
no Secret there is no account and no way to make one through the web interface.

```shell
kubectl create secret generic vince \
  --from-literal=VINCE_ADMIN_NAME=admin \
  --from-literal=VINCE_ADMIN_PASSWORD="$(head -c 24 /dev/urandom | base64)"
```

## TLS belongs to the exposure

Vince can obtain its own certificate from Let's Encrypt, which wants :443
published straight at the pod. That is left off here: compose an exposure and let
it terminate TLS, the same as every other workload.

## Persistence

One embedded key-value store on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled). The volume grows with recorded traffic, not with the
number of sites.

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
metadata: { name: kurly, namespace: vince }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-vince, namespace: vince }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/vince, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: vince }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-vince, namespace: vince }
spec: { sourceRef: { kind: OCIRepository, name: kurly-vince } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: vince, namespace: vince }
spec:
  serviceAccountName: vince-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/vince/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-vince, importPath: github.com/metio/kurly/workloads/vince }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: vince, namespace: vince }
spec:
  serviceAccountName: vince-deployer
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
        name: vince
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: vince }
```

<!-- END generated: jaas-deploy -->
