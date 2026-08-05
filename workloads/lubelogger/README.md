<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# lubelogger

[LubeLogger](https://github.com/hargata/lubelog) — vehicle maintenance records:
services, fuel stops, repairs and reminders per vehicle, with receipts attached. A
plain composable `kurly.http` workload keeping its LiteDB database and uploaded
documents on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local lubelogger = import 'github.com/metio/kurly/workloads/lubelogger/server.libsonnet';

kurly.list(lubelogger())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `lubelogger` | |
| `image` | `ghcr.io/hargata/lubelogger:v1.7.0` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | `/App/data` |
| `env` / `resources` / `labels` / `annotations` | | |

## `HOME` keeps the encryption keys

ASP.NET writes its DataProtection keys under `$HOME`, and those keys decrypt the
auth cookies and anything else it protected. Upstream's compose mounts
`/root/.aspnet/DataProtection-Keys` as a **second volume** for exactly this reason.

Pointing `HOME` at the data volume puts them on the volume already present, and
stops the path depending on which uid runs. Without it nothing fails — the keys are
simply regenerated on every start, which logs everybody out and makes previously
protected values unreadable.

## Persistence

One LiteDB file on a ReadWriteOnce volume, so this is **one replica, recreated**
(never rolled).

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
metadata: { name: kurly, namespace: lubelogger }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-lubelogger, namespace: lubelogger }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/lubelogger, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: lubelogger }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-lubelogger, namespace: lubelogger }
spec: { sourceRef: { kind: OCIRepository, name: kurly-lubelogger } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: lubelogger, namespace: lubelogger }
spec:
  serviceAccountName: lubelogger-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/lubelogger/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-lubelogger, importPath: github.com/metio/kurly/workloads/lubelogger }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: lubelogger, namespace: lubelogger }
spec:
  serviceAccountName: lubelogger-deployer
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
        name: lubelogger
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: lubelogger }
```

<!-- END generated: jaas-deploy -->
