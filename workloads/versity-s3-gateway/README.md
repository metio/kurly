<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# versity-s3-gateway

[Versity S3 Gateway](https://www.versity.com/products/versitygw/) — puts an S3
API in front of an ordinary filesystem, so tools that speak S3 can read and write
a PersistentVolume. A plain composable `kurly.http` workload: the gateway itself
is stateless and every object is a file on the volume it serves.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local versitygw = import 'github.com/metio/kurly/workloads/versity-s3-gateway/gateway.libsonnet';

kurly.list(versitygw(secretName='versitygw', storageSize='500Gi'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `versity-s3-gateway` | |
| `image` | the pinned upstream image | |
| `storageSize` / `storageClass` | `100Gi` / cluster default | the served volume (`/data`) |
| `accessModes` | `['ReadWriteOnce']` | |
| `secretName` | none | `ROOT_ACCESS_KEY` and `ROOT_SECRET_KEY` |
| `region` | `us-east-1` | the region reported to clients |
| `env` | `{}` | any other `VGW_*` setting |
| `resources` / `labels` / `annotations` | | |

Serves the S3 API on `:7070` — compose an exposure onto it. S3 clients using
virtual-host addressing need a wildcard hostname; path-style addressing is what
works behind a single name.

## The volume is the bucket namespace

A top-level directory under the served path is a bucket, and the objects in it
are files. That is what makes this useful — data written through S3 stays
readable as ordinary files, and files put there by something else appear as
objects — and it is also the constraint: object keys have to be legal paths, and
the filesystem's own limits become the gateway's.

## Root credentials

`secretName` carries `ROOT_ACCESS_KEY` and `ROOT_SECRET_KEY`, the account that can
do anything through the gateway. It is the equivalent of a root account rather
than a user, so it belongs in a Secret and not in an application's configuration.

Single writer: one ReadWriteOnce volume, so one replica, recreated. A
ReadWriteMany volume allows several gateways, and whether concurrent writers are
safe is then a question about that filesystem, not about this stage.

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
metadata: { name: kurly, namespace: versity-s3-gateway }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-versity-s3-gateway, namespace: versity-s3-gateway }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/versity-s3-gateway, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: versity-s3-gateway }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-versity-s3-gateway, namespace: versity-s3-gateway }
spec: { sourceRef: { kind: OCIRepository, name: kurly-versity-s3-gateway } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: versity-s3-gateway, namespace: versity-s3-gateway }
spec:
  serviceAccountName: versity-s3-gateway-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local gateway = import 'github.com/metio/kurly/workloads/versity-s3-gateway/gateway.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(gateway())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-versity-s3-gateway, importPath: github.com/metio/kurly/workloads/versity-s3-gateway }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: versity-s3-gateway, namespace: versity-s3-gateway }
spec:
  serviceAccountName: versity-s3-gateway-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: gateway
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: versity-s3-gateway
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: versity-s3-gateway }
```

<!-- END generated: jaas-deploy -->
