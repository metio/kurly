<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# questdb

[QuestDB](https://questdb.com) — a time-series database that ingests fast and
answers SQL, with a web console, a PostgreSQL-wire endpoint and a line-protocol
ingest port. A plain composable `kurly.http` workload: everything it stores is one
directory on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local questdb = import 'github.com/metio/kurly/workloads/questdb/server.libsonnet';

kurly.list(questdb(storageSize='200Gi'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `questdb` | |
| `image` | the pinned upstream image | |
| `storageSize` / `storageClass` | `50Gi` / cluster default | the data directory (`/var/lib/questdb`) |
| `env` | `{}` | any `QDB_*` / `QUESTDB_*` setting |
| `resources` / `labels` / `annotations` | | |

## Three ports, three audiences

| Port | |
|---|---|
| `9000` | the web console and the REST API |
| `8812` | the PostgreSQL wire protocol, so existing clients and BI tools connect unchanged |
| `9009` | InfluxDB line protocol, for ingest |

All three are on the Service. Expose only the ones that should be reachable, and
note that the console has no authentication of its own in the open-source build —
an exposure without something in front of it publishes the database.

## Running it unprivileged

The image's entrypoint chowns its data directory and re-execs through `gosu` only
when it starts as root; started as an ordinary user it runs the server directly.
So this stage uses the image's own uid 10001 with `fsGroup`, and no privilege is
relaxed.

Single writer: QuestDB is one process owning one data directory on a
ReadWriteOnce volume, so one replica, recreated — two would corrupt the tables
rather than share them.

The memory limit is what QuestDB may map for its column files, not a JVM heap
cap; a busy instance wants more than the default.

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
metadata: { name: kurly, namespace: questdb }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-questdb, namespace: questdb }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/questdb, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: questdb }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-questdb, namespace: questdb }
spec: { sourceRef: { kind: OCIRepository, name: kurly-questdb } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: questdb, namespace: questdb }
spec:
  serviceAccountName: questdb-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/questdb/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-questdb, importPath: github.com/metio/kurly/workloads/questdb }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: questdb, namespace: questdb }
spec:
  serviceAccountName: questdb-deployer
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
        name: questdb
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: questdb }
```

<!-- END generated: jaas-deploy -->
