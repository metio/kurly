<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# oxicloud

[OxiCloud](https://github.com/AtalayaLabs/OxiCloud) — file storage and sharing
with a web interface, written in Rust. A plain composable `kurly.http` workload:
the files themselves go to a PersistentVolume and the metadata to an external
PostgreSQL.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local oxicloud = import 'github.com/metio/kurly/workloads/oxicloud/server.libsonnet';

kurly.list(oxicloud(
  secretName='oxicloud',
  baseUrl='https://files.example.com',
))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `oxicloud` | |
| `image` | the pinned upstream image | |
| `storageSize` / `storageClass` | `50Gi` / cluster default | the blob store (`/app/storage`) |
| `baseUrl` | none | the URL a browser reaches this at |
| `secretName` | none | `OXICLOUD_DB_CONNECTION_STRING` |
| `env` | `{}` | any other `OXICLOUD_*` setting |
| `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:8086` — compose an exposure onto it.

## Base URL

`baseUrl` is what OxiCloud builds share links and OIDC redirects from. Behind a
reverse proxy it has to be the address a browser reaches, not the Service name —
share links that resolve only inside the cluster are this value left at its
default.

## Running it unprivileged

The image's entrypoint chowns the storage volume and drops privileges with
`su-exec` when it starts as root, and says in as many words that a start as an
unprivileged user assumes the volume permissions are already right — which is what
`fsGroup` does. So this stage runs as the image's own uid 1001 and keeps the
hardened posture rather than taking the root path.

Single writer: the blob store is one directory on a ReadWriteOnce volume, so one
replica, recreated.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**rendered** — this workload renders and validates against the Kubernetes schemas with its defaults.

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
metadata: { name: kurly, namespace: oxicloud }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-oxicloud, namespace: oxicloud }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/oxicloud, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: oxicloud }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-oxicloud, namespace: oxicloud }
spec: { sourceRef: { kind: OCIRepository, name: kurly-oxicloud } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: oxicloud, namespace: oxicloud }
spec:
  serviceAccountName: oxicloud-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/oxicloud/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-oxicloud, importPath: github.com/metio/kurly/workloads/oxicloud }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: oxicloud, namespace: oxicloud }
spec:
  serviceAccountName: oxicloud-deployer
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
        name: oxicloud
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: oxicloud }
```

<!-- END generated: jaas-deploy -->
