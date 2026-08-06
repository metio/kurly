<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# safebucket

[Safebucket](https://github.com/safebucket/safebucket) — file sharing where the
bytes never touch the server: the API mints presigned URLs and the browser
uploads to and downloads from S3-compatible storage directly, so the server holds
only metadata and access control. A composable `kurly.http` workload backed by an
external PostgreSQL and an external S3 bucket.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local safebucket = import 'github.com/metio/kurly/workloads/safebucket/server.libsonnet';

kurly.list(safebucket())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `safebucket` | |
| `image` | `ghcr.io/safebucket/safebucket:0.7.2` | |
| `apiUrl` / `webUrl` / `allowedOrigins` | `https://safebucket.example.com` | the URLs a **browser** reaches |
| `adminEmail` | `admin@example.com` | the first account, created on start |
| `dbHost` / `dbPort` / `database` / `dbUser` / `dbSslMode` | `safebucket-db-rw` … | pairs with a `cnpg-cluster` named `safebucket-db` |
| `s3Endpoint` | `seaweedfs-s3:8333` | `host:port` as the **server** reaches it, no scheme |
| `s3ExternalEndpoint` | `https://s3.example.com` | absolute URL a **browser** reaches |
| `s3Bucket` / `s3Region` / `s3UseTls` | `safebucket` / `us-east-1` / `false` | |
| `secretName` | `safebucket` | six credentials, see below |

## The two endpoints are not the same address

Uploads and downloads are presigned and executed by the browser, so the signature
has to be made for the address the browser will use. `s3Endpoint` is how the pod
reaches the store (a cluster Service); `s3ExternalEndpoint` is the public URL of
the same bucket. Set them to the same value only if the store is reachable at one
address from both places. The bucket must already exist and must allow CORS from
`webUrl` — Safebucket verifies the bucket on start and stops when it is missing,
and a bucket without CORS produces a UI that loads and an upload the browser
refuses.

## Supply the Secret

Nothing here has a default; the server refuses to start until each is set.

| key | what it is |
|---|---|
| `APP__TOKEN_SECRET` | signs the tokens users hold |
| `APP__MFA_ENCRYPTION_KEY` | encrypts stored MFA secrets — **exactly 32 characters** |
| `APP__ADMIN_PASSWORD` | the password of the `adminEmail` account |
| `DATABASE__POSTGRES__PASSWORD` | the database login |
| `STORAGE__S3__ACCESS_KEY` / `STORAGE__S3__SECRET_KEY` | the bucket credentials |

## What it does not keep

Metadata is in PostgreSQL and objects are in the bucket, so the pod itself is
stateless and `/app/data` is an emptyDir. The filesystem notifier and the activity
log write there and go with the pod: set `NOTIFIER__TYPE=smtp` (with the
`NOTIFIER__SMTP__*` settings) and `ACTIVITY__TYPE=loki` through `env` to keep
either. `CACHE__TYPE` and `EVENTS__TYPE` default to the in-process
implementations, which is what makes a single replica self-sufficient; more than
one replica wants a Redis or Valkey and a NATS.

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
metadata: { name: kurly, namespace: safebucket }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-safebucket, namespace: safebucket }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/safebucket, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: safebucket }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-safebucket, namespace: safebucket }
spec: { sourceRef: { kind: OCIRepository, name: kurly-safebucket } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: safebucket, namespace: safebucket }
spec:
  serviceAccountName: safebucket-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/safebucket/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-safebucket, importPath: github.com/metio/kurly/workloads/safebucket }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: safebucket, namespace: safebucket }
spec:
  serviceAccountName: safebucket-deployer
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
        name: safebucket
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: safebucket }
```

<!-- END generated: jaas-deploy -->
