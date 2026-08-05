<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# picoshare

[PicoShare](https://github.com/mtlynch/picoshare) — a minimal file-sharing app.
Upload a file, get a link, optionally one that expires. A plain composable
`kurly.http` workload.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local picoshare = import 'github.com/metio/kurly/workloads/picoshare/server.libsonnet';

kurly.list(picoshare())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `picoshare` | |
| `image` | `mtlynch/picoshare:v1.5.4` | |
| `storageSize` | `20Gi` | sized for the **files**, see below |
| `storageClass` | cluster default | |
| `secretName` | `picoshare` | supplies `PS_SHARED_SECRET` |
| `env` / `resources` / `labels` / `annotations` | | |

Serves on `:4001`:

```jsonnet
kurly.list([
  picoshare()
  + kurly.expose.ownGateway('share.example.com', 'istio', tls='picoshare-tls'),
  kurly.certificate('picoshare-tls', ['share.example.com'], 'letsencrypt-prod'),
])
```

## The database *is* the data

PicoShare stores uploaded file **contents** as blobs inside its SQLite database,
not on the filesystem beside it. So `/data/store.db` grows with every upload, and
`storageSize` has to be sized for everything you intend to host rather than for an
index. This also makes backups pleasantly simple — one file is the whole
service — and makes it worth knowing before you give it a 1Gi volume.

## One passphrase is the whole security model

`PS_SHARED_SECRET` grants upload *and* administration. PicoShare has a single
account, and this is it — there is nothing else between a visitor and the ability
to upload.

```shell
kubectl create secret generic picoshare \
  --from-literal=PS_SHARED_SECRET="$(head -c 18 /dev/urandom | base64 | tr -d '/+=')"
```

Downloads of shared links do not need it, which is the point of the app.

## Persistence

One SQLite database on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled). The image's own command already points the database at
`/data/store.db`, so the volume mounts there and nothing has to override an
argument.

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
metadata: { name: kurly, namespace: picoshare }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-picoshare, namespace: picoshare }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/picoshare, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: picoshare }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-picoshare, namespace: picoshare }
spec: { sourceRef: { kind: OCIRepository, name: kurly-picoshare } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: picoshare, namespace: picoshare }
spec:
  serviceAccountName: picoshare-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/picoshare/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-picoshare, importPath: github.com/metio/kurly/workloads/picoshare }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: picoshare, namespace: picoshare }
spec:
  serviceAccountName: picoshare-deployer
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
        name: picoshare
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: picoshare }
```

<!-- END generated: jaas-deploy -->
