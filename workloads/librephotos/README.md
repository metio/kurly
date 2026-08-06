<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# librephotos

[LibrePhotos](https://docs.librephotos.com) — a self-hosted photo library that recognises the
faces, places and objects in your pictures. It runs as **three stages**, which is what the
application really is: the `backend` (the Django/gunicorn API, the django-q worker, and the
machine-learning models those services load), the `frontend` (the built React app, served as
static files) and the `proxy` (the nginx edge that joins the two into one origin). PostgreSQL is
external; the task queue is django-q on the ORM broker, so there is **no Redis**.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local backend = import 'github.com/metio/kurly/workloads/librephotos/backend.libsonnet';
local frontend = import 'github.com/metio/kurly/workloads/librephotos/frontend.libsonnet';
local proxy = import 'github.com/metio/kurly/workloads/librephotos/proxy.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.list([
  cnpg(name='librephotos-db', database='librephotos'),
  backend(),
  frontend(),
  // The one stage that faces the browser.
  proxy() + kurly.expose.ingress('photos.example.com'),
  // The Secret the backend reads; fill it from the cnpg cluster's own
  // librephotos-db-app Secret, or from your secret store.
  kurly.externalSecret('librephotos', { name: 'vault', kind: 'ClusterSecretStore' }, [
    { secretKey: 'DB_PASS', remoteRef: { key: 'librephotos/db', property: 'password' } },
    { secretKey: 'SECRET_KEY', remoteRef: { key: 'librephotos/django', property: 'secret_key' } },
    { secretKey: 'ADMIN_PASSWORD', remoteRef: { key: 'librephotos/admin', property: 'password' } },
  ]),
])
```

**Expose the proxy, and only the proxy.** The frontend assets are not a working install on their
own — the browser expects `/api` and `/media` on the same origin — and the backend answers 401 to
everything without a JWT. The proxy serves the app on `:8080`.

## The nginx configuration is rendered, not the image's

The proxy image ships an `nginx.conf` whose upstreams are the literal host names `backend` and
`frontend`. No namespace can run two copies of that, and neither can one that already has a
Service by either name. The `proxy` stage therefore renders its own equivalent from
`backendHost` / `frontendHost` (defaulting to the sibling stages under the same `namePrefix`) and
mounts it as a single file, so the whole workload follows `namePrefix`. It keeps the upstream's
Content-Security-Policy — MapLibre GL needs the inline and blob sources plus the tile and glyph
hosts of the map providers Site Settings offers — and its `internal` locations, which are the
second half of the backend's `X-Accel-Redirect`: Django authorises a download and answers with a
path only nginx may serve.

## Storage: one volume, two pods

The backend owns a single volume at `/librephotos`, which is what `BASE_DATA` and `BASE_LOGS`
point at:

| path | holds |
| --- | --- |
| `/librephotos/data` | the photo library — the originals you upload or scan |
| `/librephotos/protected_media` | thumbnails, face crops and the downloaded ML models; plan for several times the library |
| `/librephotos/logs` | the logs **and Django's `secret.key`** — losing it logs every session out |

The proxy mounts that same claim **read-only**, because the media files are served straight off
disk. With the `ReadWriteOnce` default the two pods must land on the same node; pass a
ReadWriteMany `storageClass` (and `accessModes`) to the backend to spread them, or set
`serveMedia=false` on the proxy to drop the mount — downloads and full-size images then 404.

## First start takes a while

The backend's entrypoint applies the whole Django migration set, collects static files, starts the
ML services and builds the similarity index before gunicorn binds. That is minutes on a cold
volume, which is why the stage carries a generous startup probe rather than a long liveness delay.
`adminUsername` / `adminEmail` create the first account from `ADMIN_PASSWORD` in the Secret; set
`adminUsername=null` once it exists. `workerConcurrency` sizes the django-q pool — left unset it
sizes itself from the **node's** core count, and a CPU limit only starves it.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**e2e** — this workload is deployed to a live cluster by a smoke scenario and observed reaching readiness, on top of its test coverage.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stages with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
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
metadata: { name: kurly, namespace: librephotos }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-librephotos, namespace: librephotos }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/librephotos, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: librephotos }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-librephotos, namespace: librephotos }
spec: { sourceRef: { kind: OCIRepository, name: kurly-librephotos } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: librephotos-backend, namespace: librephotos }
spec:
  serviceAccountName: librephotos-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local backend = import 'github.com/metio/kurly/workloads/librephotos/backend.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(backend())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-librephotos, importPath: github.com/metio/kurly/workloads/librephotos }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: librephotos-frontend, namespace: librephotos }
spec:
  serviceAccountName: librephotos-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local frontend = import 'github.com/metio/kurly/workloads/librephotos/frontend.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(frontend())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-librephotos, importPath: github.com/metio/kurly/workloads/librephotos }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: librephotos-proxy, namespace: librephotos }
spec:
  serviceAccountName: librephotos-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local proxy = import 'github.com/metio/kurly/workloads/librephotos/proxy.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(proxy())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-librephotos, importPath: github.com/metio/kurly/workloads/librephotos }
```

A `StageSet` deploys the stages in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: librephotos, namespace: librephotos }
spec:
  serviceAccountName: librephotos-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: backend
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: librephotos-backend
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: librephotos-backend }
    - name: frontend
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: librephotos-frontend
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: librephotos-frontend }
    - name: proxy
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: librephotos-proxy
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: librephotos-proxy }
```

<!-- END generated: jaas-deploy -->
