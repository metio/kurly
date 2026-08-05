<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# cloudreve

[Cloudreve](https://github.com/cloudreve/cloudreve) — self-hosted file storage and
sharing with a web UI. Upload, organise and share files, backed by local disk or by
any S3-style object storage you point it at. A plain composable `kurly.http`
workload: the SQLite database, configuration and (by default) the stored files all
live on one PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local cloudreve = import 'github.com/metio/kurly/workloads/cloudreve/server.libsonnet';

kurly.list(cloudreve())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `cloudreve` | |
| `image` | `cloudreve/cloudreve:4.9.2` | |
| `storageSize` / `storageClass` | `20Gi` / cluster default | `/cloudreve/data` |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web UI and API on `:5212`:

```jsonnet
kurly.list([
  cloudreve()
  + kurly.expose.ownGateway('files.example.com', 'istio', tls='cloudreve-tls'),
  kurly.certificate('cloudreve-tls', ['files.example.com'], 'letsencrypt-prod'),
])
```

**The first start prints an administrator password to the log.** Read it from
`kubectl logs` before anybody else does, and change it.

## Running unprivileged

The image starts as root and drops nothing — but it needs nothing root provides:
every port it binds is above 1024, and the only path it writes is its data
directory. So this names an unprivileged uid and keeps the **restricted** posture,
with `fsGroup` making the volume writable.

Two scratch directories cover what is written outside that volume: the entrypoint
starts `supervisord` for the bundled aria2 downloader before the server, and
supervisord wants somewhere for its socket and pid.

## Persistence

One SQLite database on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled) to keep two pods off the file. Both halves can move off
the volume from Cloudreve's own settings: PostgreSQL for the database, S3-style
object storage for the files — at which point the volume holds only configuration.

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
metadata: { name: kurly, namespace: cloudreve }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-cloudreve, namespace: cloudreve }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/cloudreve, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: cloudreve }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-cloudreve, namespace: cloudreve }
spec: { sourceRef: { kind: OCIRepository, name: kurly-cloudreve } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: cloudreve, namespace: cloudreve }
spec:
  serviceAccountName: cloudreve-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/cloudreve/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-cloudreve, importPath: github.com/metio/kurly/workloads/cloudreve }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: cloudreve, namespace: cloudreve }
spec:
  serviceAccountName: cloudreve-deployer
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
        name: cloudreve
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: cloudreve }
```

<!-- END generated: jaas-deploy -->
