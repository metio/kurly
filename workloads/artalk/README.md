<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# artalk

[Artalk](https://github.com/ArtalkJS/Artalk) — a self-hosted comment system: a
small script on a page posts to this backend, which keeps the threads, moderates
them and sends the notifications. A plain composable `kurly.http` workload; the
SQLite database, the generated configuration, the log and the uploaded images all
live on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local artalk = import 'github.com/metio/kurly/workloads/artalk/server.libsonnet';

kurly.list(artalk(siteUrl='https://blog.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `artalk` | |
| `image` | `artalk/artalk-go:2.10.0` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | `/data` |
| `siteUrl` | unset | the address readers reach, not the Service |
| `siteDefault` | `Default Site` | the name Artalk files comments under |
| `locale` / `timezone` | `en` / `UTC` | |
| `secretName` | `artalk` | holds `ATK_APP_KEY` |
| `env` / `resources` / `labels` / `annotations` | | |

## The administrator is not created for you

Artalk mints the first administrator through its own CLI, so plan on one
`kubectl exec` after the first roll:

```shell
kubectl exec -it deploy/artalk -- artalk admin
```

Until that is done the dashboard has nobody to log in as. There is nothing in
this workload that can do it — the command is interactive.

## siteUrl is a deployment fact

`siteUrl` is the address a reader's browser reaches, not the in-cluster Service.
Artalk builds the links in the notification mails it sends from it, so leaving it
unset sends mail pointing nowhere. It has no sane default, which is why there is
none here.

## Persistence

Everything Artalk keeps is under `/data`: the SQLite database, the configuration
its entrypoint generates on first start, the log, and uploaded images. That is
one writer on a ReadWriteOnce volume, so **one replica, recreated** (never
rolled).

`ATK_DB_FILE` and `ATK_LOG_FILENAME` are set absolutely. The generated
configuration names them relative to the working directory, which lands on the
volume only because the image happens to set none — naming them outright means
the database does not move the day that changes.

## The signing key

`secretName` holds `ATK_APP_KEY`, which signs the JWTs users and administrators
hold. Artalk writes one into its configuration file when unset, so it survives a
restart here — the configuration is on the volume — but not a move to a fresh
one. Supplying it makes sessions outlive the volume.

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
metadata: { name: kurly, namespace: artalk }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-artalk, namespace: artalk }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/artalk, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: artalk }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-artalk, namespace: artalk }
spec: { sourceRef: { kind: OCIRepository, name: kurly-artalk } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: artalk, namespace: artalk }
spec:
  serviceAccountName: artalk-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/artalk/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-artalk, importPath: github.com/metio/kurly/workloads/artalk }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: artalk, namespace: artalk }
spec:
  serviceAccountName: artalk-deployer
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
        name: artalk
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: artalk }
```

<!-- END generated: jaas-deploy -->
