<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# quickwit

[Quickwit](https://quickwit.io) — a search engine for logs, traces and other
append-only data, built to index straight onto object storage. A plain composable
`kurly.http` workload running every Quickwit service in one process.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local quickwit = import 'github.com/metio/kurly/workloads/quickwit/server.libsonnet';

kurly.list(quickwit(
  defaultIndexRootUri='s3://logs/indexes',
  secretName='quickwit-objectstore',
))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `quickwit` | |
| `image` | the pinned upstream image | |
| `storageSize` / `storageClass` | `20Gi` / cluster default | the data directory (`/quickwit/qwdata`) |
| `defaultIndexRootUri` | none | where index splits are written |
| `secretName` | none | object-storage credentials, read through `envFrom` |
| `env` | `{}` | any other `QW_*` setting |
| `resources` / `labels` / `annotations` | | |

Serves the REST API, the UI and the Elasticsearch-compatible API on `:7280` —
compose an exposure onto it.

## Where the index lives

By default the whole index is on the PersistentVolume, which is the arrangement
that works with no other infrastructure and does not grow past one node.
`defaultIndexRootUri` pointed at an S3 bucket (`s3://bucket/indexes`) is what
Quickwit is actually built for: the split files go to object storage and the
volume keeps only the metastore and local caches. The credentials for that bucket
come from `secretName` (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) — kurly
authors no Secret.

Single writer: the file-backed metastore is one directory on a ReadWriteOnce
volume, so one replica, recreated. A cluster wants a PostgreSQL metastore and
separately scaled indexer and searcher roles, which is a different arrangement
than this one stage.

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
metadata: { name: kurly, namespace: quickwit }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-quickwit, namespace: quickwit }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/quickwit, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: quickwit }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-quickwit, namespace: quickwit }
spec: { sourceRef: { kind: OCIRepository, name: kurly-quickwit } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: quickwit, namespace: quickwit }
spec:
  serviceAccountName: quickwit-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/quickwit/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-quickwit, importPath: github.com/metio/kurly/workloads/quickwit }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: quickwit, namespace: quickwit }
spec:
  serviceAccountName: quickwit-deployer
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
        name: quickwit
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: quickwit }
```

<!-- END generated: jaas-deploy -->
