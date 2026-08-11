<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mcp-context-forge

[MCP Context Forge](https://github.com/IBM/mcp-context-forge) — a registry and
proxy that federates MCP servers, A2A servers and REST APIs behind one endpoint,
with authentication, rate limiting and an admin UI. A plain composable
`kurly.http` workload: the registry lives in a SQLite database on a
PersistentVolume, so a single instance needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local forge = import 'github.com/metio/kurly/workloads/mcp-context-forge/server.libsonnet';

kurly.list(forge(secretName='mcp-context-forge'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `mcp-context-forge` | |
| `image` | the pinned upstream image | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the SQLite database (`/app/data`) |
| `databaseUrl` | `sqlite:////app/data/mcp.db` | a SQLAlchemy URL |
| `secretName` | none | see below |
| `env` | `{}` | |
| `resources` / `labels` / `annotations` | | |

Serves the gateway, the admin UI and the API on `:4444` — compose an exposure onto
it.

## Secrets

`secretName` is required in any real deployment. It carries `JWT_SECRET_KEY`,
which signs the tokens the gateway issues — a value that changes on restart
invalidates every one of them — and the platform admin's credentials. The gateway
also stores the credentials of every upstream server it federates, which is what
makes the database worth backing up.

## What it reaches

The gateway's whole job is to call other servers, so it can reach whatever the pod
can reach, including anything else in the cluster. A NetworkPolicy limiting its
egress to the servers it is meant to federate is worth composing on:

```jsonnet
forge(secretName='mcp-context-forge')
+ kurly.network.kubernetes(allowTo=[{ pods: { app: 'weather-mcp' }, ports: [8080] }])
```

Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
recreated. Point `databaseUrl` at PostgreSQL to run more than one.

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
metadata: { name: kurly, namespace: mcp-context-forge }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-mcp-context-forge, namespace: mcp-context-forge }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/mcp-context-forge, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: mcp-context-forge }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-mcp-context-forge, namespace: mcp-context-forge }
spec: { sourceRef: { kind: OCIRepository, name: kurly-mcp-context-forge } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: mcp-context-forge, namespace: mcp-context-forge }
spec:
  serviceAccountName: mcp-context-forge-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/mcp-context-forge/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-mcp-context-forge, importPath: github.com/metio/kurly/workloads/mcp-context-forge }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: mcp-context-forge, namespace: mcp-context-forge }
spec:
  serviceAccountName: mcp-context-forge-deployer
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
        name: mcp-context-forge
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: mcp-context-forge }
```

<!-- END generated: jaas-deploy -->
