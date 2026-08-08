<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# our-shopping-list

[Our Shopping List](https://codeberg.org/nanawel/our-shopping-list) — shared
shopping and todo lists, synchronised live between everyone looking at a board. A
plain composable `kurly.http` workload on the official image, backed by an external
MongoDB.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local osl = import 'github.com/metio/kurly/workloads/our-shopping-list/server.libsonnet';

kurly.list(osl(dbHost='mongodb.example.svc'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `our-shopping-list` | |
| `image` | `ourshoppinglist/our-shopping-list:4.2.0` | |
| `replicas` | `2` | stateless |
| `port` | `8080` | also `LISTEN_PORT` |
| `dbHost` / `dbPort` / `dbName` | `mongodb` / `27017` / `osl` | |
| `baseUrl` | unset | when it is not served at the web root, e.g. `/osl/` |
| `env` / `resources` / `labels` / `annotations` | | |

## The database takes no password

The connection is a host, a port and a database name, and nothing else — upstream
states MongoDB authentication is **not supported yet**, so there is no credential to
put in a Secret and none is declared. Reach the database over a network it is not
otherwise exposed on rather than with a password it will not read:

```jsonnet
osl(dbHost='mongodb.example.svc')
+ kurly.network.kubernetes(allowTo=[{ pods: { 'app.kubernetes.io/name': 'mongodb' }, ports: [27017] }])
```

## Live updates are a WebSocket

Boards update under everyone watching them over socket.io. An exposure that does not
upgrade the connection leaves a UI that loads, works for the person typing, and never
moves for anybody else — no error anywhere.

## Persistence

None here. Every board and item lives in MongoDB and the client bundle is baked into
the image, so this is a plain rolling Deployment that scales freely.

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
metadata: { name: kurly, namespace: our-shopping-list }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-our-shopping-list, namespace: our-shopping-list }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/our-shopping-list, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: our-shopping-list }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-our-shopping-list, namespace: our-shopping-list }
spec: { sourceRef: { kind: OCIRepository, name: kurly-our-shopping-list } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: our-shopping-list, namespace: our-shopping-list }
spec:
  serviceAccountName: our-shopping-list-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/our-shopping-list/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-our-shopping-list, importPath: github.com/metio/kurly/workloads/our-shopping-list }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: our-shopping-list, namespace: our-shopping-list }
spec:
  serviceAccountName: our-shopping-list-deployer
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
        name: our-shopping-list
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: our-shopping-list }
```

<!-- END generated: jaas-deploy -->
