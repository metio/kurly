<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# pictshare

[PictShare](https://github.com/HaschekSolutions/pictshare) — image, video and
paste hosting with a resizing URL API: the size, rotation and format are path
segments, so `/300x300/filter/name.jpg` asks for a variant and the server produces
it. A plain composable `kurly.http` workload keeping the uploads on a
PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local pictshare = import 'github.com/metio/kurly/workloads/pictshare/server.libsonnet';

kurly.list(pictshare())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `pictshare` | |
| `image` | `ghcr.io/hascheksolutions/pictshare:3.3.0` | |
| `storageSize` / `storageClass` | `20Gi` / cluster default | `/app/public/data` |
| `secretName` | `pictshare` | upload, delete and admin codes |
| `env` / `resources` / `labels` / `annotations` | | |

## Anyone who can reach it can upload

That is PictShare's design, not an oversight: with no `UPLOAD_CODE` and no
`ALLOWED_SUBNET` the upload endpoint is open to whoever can reach the Service. On
an exposed instance that is a public file host with your storage bill attached, so
the Secret is what makes it yours:

```shell
kubectl create secret generic pictshare \
  --from-literal=UPLOAD_CODE="$(head -c 24 /dev/urandom | base64)" \
  --from-literal=MASTER_DELETE_CODE="$(head -c 24 /dev/urandom | base64)" \
  --from-literal=ADMIN_PASSWORD="$(head -c 24 /dev/urandom | base64)"
```

`UPLOAD_CODE` is then required on every upload, `MASTER_DELETE_CODE` deletes any
file, and `ADMIN_PASSWORD` opens the admin page. `ALLOWED_SUBNET` (a
comma-separated CIDR list, in `env`) restricts uploads by address instead, which
only means anything if the exposure preserves the client address.

## Why this one is less hardened

Everything the entrypoint does before serving needs a writable image: it rewrites
`php.ini` in place for the upload limit, writes its configuration into the
application tree as `src/inc/config.inc.php`, creates and chmods
`/app/public/tmp`, and starts a local `redis-server` with a socket under `/run`.
So the root filesystem is writable and the container runs as root.

Two capabilities come back on top of the dropped-ALL default. Caddy binds `:80`:
the FrankenPHP binary carries the file capability for it, but a file capability is
worthless when the bounding set does not hold it, so `NET_BIND_SERVICE` is granted
explicitly. And the redis the entrypoint starts writes its log and its dump into
directories the image gives to the `redis` account, which root may only enter with
`DAC_OVERRIDE` — dropping ALL takes that from root too, and without it redis never
starts and every page is a 500.

## The redis is a cache in the pod, not a dependency

The entrypoint starts one and PictShare uses it for metadata lookups. It is not on
the volume, so it is rebuilt from the files after a restart, and nothing outside
the pod talks to it. `REDIS_CACHING: 'false'` in `env` turns it off.

The stage defaults `REDIS_SERVER` to `localhost` and `REDIS_PORT` to `6379`, the
values the project's own compose file uses. The image's built-in default names a
unix socket *and* a port, and phpredis reads a socket path as a hostname the
moment a port comes with it — so the front page fails with `getaddrinfo` on a file
path. Anything you pass in `env` still wins.

## Persistence

Uploads live at `/app/public/data` on a ReadWriteOnce volume, so this is **one
replica, recreated** (never rolled). The S3 and FTP backends PictShare also
supports are configured entirely through `env`; kurly claims the volume either
way, because the local directory is still where files land first.

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
metadata: { name: kurly, namespace: pictshare }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-pictshare, namespace: pictshare }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/pictshare, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: pictshare }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-pictshare, namespace: pictshare }
spec: { sourceRef: { kind: OCIRepository, name: kurly-pictshare } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: pictshare, namespace: pictshare }
spec:
  serviceAccountName: pictshare-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/pictshare/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-pictshare, importPath: github.com/metio/kurly/workloads/pictshare }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: pictshare, namespace: pictshare }
spec:
  serviceAccountName: pictshare-deployer
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
        name: pictshare
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: pictshare }
```

<!-- END generated: jaas-deploy -->
