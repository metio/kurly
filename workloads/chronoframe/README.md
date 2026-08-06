<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# chronoframe

[ChronoFrame](https://github.com/HoshinoSuzumi/chronoframe) — a personal photo
gallery that browses your own pictures by map, timeline and EXIF. A plain
composable `kurly.http` workload keeping its SQLite database, and by default the
photos themselves, on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local chronoframe = import 'github.com/metio/kurly/workloads/chronoframe/server.libsonnet';

kurly.list(chronoframe())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `chronoframe` | |
| `image` | `ghcr.io/hoshinosuzumi/chronoframe:1.0.0-rc.4` | |
| `storageSize` / `storageClass` | `20Gi` / cluster default | `/app/data` |
| `adminEmail` | `admin@chronoframe.com` | the account created on first start |
| `secretName` | `chronoframe` | session password, OG signing key, admin password |
| `env` / `resources` / `labels` / `annotations` | | `env` merges over the defaults |

## Where the photos go

The image ships with the **S3** storage provider selected, which cannot work
until somebody supplies a bucket — so this stage selects the **local** provider
instead. A default render stores photos under `/app/data/storage` on the volume
and needs nothing else. Sizing follows from that: `20Gi` is a starting point for
a gallery, not a database default.

Moving them off is `env`, since the keys are the app's own:

```jsonnet
chronoframe(storageSize='2Gi', env={
  NUXT_STORAGE_PROVIDER: 's3',
  NUXT_PROVIDER_S3_ENDPOINT: 'https://s3.example.com',
  NUXT_PROVIDER_S3_BUCKET: 'photos',
})
```

The S3 credentials belong in the Secret, not in `env`.

## The Secret

```shell
kubectl create secret generic chronoframe \
  --from-literal=NUXT_SESSION_PASSWORD="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')" \
  --from-literal=NUXT_OG_IMAGE_SECRET="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')" \
  --from-literal=CFRAME_ADMIN_PASSWORD="$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"
```

`NUXT_SESSION_PASSWORD` encrypts the session cookie and must be **32 characters**
— a shorter one is refused at start. Without `CFRAME_ADMIN_PASSWORD` the image
creates its administrator with a password published in its own documentation, so
supply one before the gallery is reachable by anyone else.

## It needs egress, which is easy to forget

Map tiles, reverse geocoding and (if enabled) GitHub OAuth are fetched over the
internet at runtime. A NetworkPolicy written from the shape of the manifest
blocks all three, and the failure is quiet: the gallery works and the map stays
blank.

```jsonnet
chronoframe() + kurly.network.kubernetes(allowTo=[{ cidr: '0.0.0.0/0', ports: [443] }])
```

## Persistence

One SQLite database on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled).

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
metadata: { name: kurly, namespace: chronoframe }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-chronoframe, namespace: chronoframe }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/chronoframe, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: chronoframe }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-chronoframe, namespace: chronoframe }
spec: { sourceRef: { kind: OCIRepository, name: kurly-chronoframe } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: chronoframe, namespace: chronoframe }
spec:
  serviceAccountName: chronoframe-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/chronoframe/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-chronoframe, importPath: github.com/metio/kurly/workloads/chronoframe }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: chronoframe, namespace: chronoframe }
spec:
  serviceAccountName: chronoframe-deployer
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
        name: chronoframe
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: chronoframe }
```

<!-- END generated: jaas-deploy -->
