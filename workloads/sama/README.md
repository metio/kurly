<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# sama

[SAMA](https://samacloud.io) — the backend of an end-to-end encrypted chat:
WebSocket and HTTP APIs for conversations, messages, devices and attachments,
with the SAMA client applications talking to it. A composable `kurly.http`
workload on the official image, backed by an external MongoDB and an external
Redis.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local sama = import 'github.com/metio/kurly/workloads/sama/server.libsonnet';

kurly.list(sama(corsOrigin='https://chat.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `sama` | |
| `image` | the pinned `sama-server` | |
| `replicas` | `2` | stateless — scale freely |
| `port` | `9001` | WebSocket and HTTP share it |
| `clusterPort` | `9002` | pod-to-pod, deliberately off the Service |
| `clusterSyncInterval` | `60000` | ms; must be set |
| `socketPingInterval` | `60000` | ms; must be set |
| `corsOrigin` | unset | the origin a browser client is served from |
| `s3Endpoint` / `s3Bucket` / `s3Region` | unset / `sama` / `us-east-1` | attachment storage |
| `secretName` | `sama` | envFrom (see below) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves on `:9001` — compose an exposure onto it, and **allow WebSocket
upgrades**: plain HTTP alone gets clients that log in and then go silent. Pairs
with a [mongodb-cluster](../mongodb-cluster/) named `sama-db`.

## Clustering

Every replica opens a second socket on `clusterPort` and registers its pod
address in Redis; a message for a user connected to a different replica is
forwarded over that socket, pod to pod, on a port no Service carries. A
NetworkPolicy that allows only the API port therefore delivers messages within a
replica and drops them between replicas — which looks like messages arriving for
some recipients and not others.

`clusterSyncInterval` and `socketPingInterval` are milliseconds and have no
default in the image: left unset they are read as `NaN`, and the timers they
drive fire continuously.

## Secrets

kurly authors none. The Secret named by `secretName` is read with `envFrom` and
holds `MONGODB_URL`, `REDIS_URL`, `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`,
`COOKIE_SECRET` and `HTTP_ADMIN_API_KEY` — plus `S3_ACCESS_KEY` and
`S3_SECRET_KEY` where attachments are configured. Rotating either JWT secret
signs everyone out.

The built-in REPL (`APP_REPL_HTTP_ACCESS_KEY`, `APP_REPL_SOCKET_HANDLER`,
`APP_REPL_FILE_IN`/`OUT`) evaluates JavaScript inside the server process and is
left unset here. Switching it on hands whoever reaches that port the process.

## Persistence

Conversations and messages live in MongoDB, sessions in Redis, attachments in
S3-compatible object storage — nothing on a volume, so this is **stateless**, a
plain rolling Deployment. Attachments are uploaded by the client against a
presigned URL the server mints, so the bucket has to be reachable from the
browser and not only from the cluster; the S3 client addresses buckets
virtual-host style and that is not configurable. Leaving object storage
unconfigured starts the server and everything but file transfer works.

Schema migrations are the image's own `npm run migrate-mongo-up` against the same
database, run as a job — startup does not run them.

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
metadata: { name: kurly, namespace: sama }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-sama, namespace: sama }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/sama, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: sama }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-sama, namespace: sama }
spec: { sourceRef: { kind: OCIRepository, name: kurly-sama } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: sama, namespace: sama }
spec:
  serviceAccountName: sama-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/sama/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-sama, importPath: github.com/metio/kurly/workloads/sama }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: sama, namespace: sama }
spec:
  serviceAccountName: sama-deployer
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
        name: sama
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: sama }
```

<!-- END generated: jaas-deploy -->
