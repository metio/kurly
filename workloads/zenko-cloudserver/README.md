<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# zenko-cloudserver

[Zenko CloudServer](https://www.zenko.io/) as a plain composable `kurly.http`
workload — an S3-compatible object storage server that keeps the objects on a
PersistentVolume and their index on a second one. It serves the S3 API on
`8000`.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local cloudserver = import 'github.com/metio/kurly/workloads/zenko-cloudserver/server.libsonnet';

kurly.list(cloudserver(endpoint='s3.example.com', dataSize='200Gi'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `zenko-cloudserver` | |
| `endpoint` | `zenko-cloudserver` | the ONE host name it answers for — see below |
| `region` | `us-east-1` | the region a client must sign for |
| `backend` | `file` | `mem` keeps nothing across a restart |
| `logLevel` | `info` | |
| `dataSize` | `50Gi` | the objects, at `/usr/src/app/localData` |
| `metadataSize` | `10Gi` | the index, at `/usr/src/app/localMetadata` |
| `storageClass` | cluster default | both claims |
| `secretName` | `zenko-cloudserver` | read with `envFrom` |

## The endpoint is part of the contract

CloudServer answers only for host names it was configured with: a request whose
`Host` header is not a known REST endpoint is refused, whatever the credentials
say. So `endpoint` must be the name clients really address — the in-cluster
Service name when it is consumed from inside the cluster, the public name when
an exposure sits in front of it.

The image's entrypoint accepts exactly one, which is why this is a string. Two
names means mounting a `config.json` of your own over the image's.

## The Secret

kurly authors no Secret. These are the S3 account an S3 client signs with, not a
login page:

| Key | What it is |
|---|---|
| `SCALITY_ACCESS_KEY_ID` | the access key |
| `SCALITY_SECRET_ACCESS_KEY` | the secret key |

## Why it runs as root on a writable root filesystem

The entrypoint reads the environment and rewrites `/usr/src/app/config.json` in
place with `jq` on every start, then fails the container if it could not. That
file sits in the image's own install tree, beside `node_modules`, and is
root-owned — so the tree can neither be mounted over nor handed to an
unprivileged user. Both relaxations are what make the image start at all, and
neither can be composed away.

## Two volumes, one writer

The objects and the index are separate claims because the image lays them out
that way, and an operator sizing an object store wants the index somewhere
faster than the blocks. Both are `ReadWriteOnce` and the metadata daemon runs
inside this pod, so it is one replica, recreated rather than rolled. Growing it
is a second CloudServer over shared metadata, not a replica count.

## Probing

Every S3 path validates the `Host` header and answers 403 without a signature,
and `/_/healthcheck` is served only to the loopback range the default config
allows — so readiness is the port accepting a connection. A first start builds
the metadata index before it listens, which is what the startup probe's budget
is for.

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
metadata: { name: kurly, namespace: zenko-cloudserver }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-zenko-cloudserver, namespace: zenko-cloudserver }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/zenko-cloudserver, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: zenko-cloudserver }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-zenko-cloudserver, namespace: zenko-cloudserver }
spec: { sourceRef: { kind: OCIRepository, name: kurly-zenko-cloudserver } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: zenko-cloudserver, namespace: zenko-cloudserver }
spec:
  serviceAccountName: zenko-cloudserver-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/zenko-cloudserver/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-zenko-cloudserver, importPath: github.com/metio/kurly/workloads/zenko-cloudserver }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: zenko-cloudserver, namespace: zenko-cloudserver }
spec:
  serviceAccountName: zenko-cloudserver-deployer
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
        name: zenko-cloudserver
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: zenko-cloudserver }
```

<!-- END generated: jaas-deploy -->
