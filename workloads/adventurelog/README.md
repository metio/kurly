<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# adventurelog

[AdventureLog](https://github.com/seanmorley15/AdventureLog) — a travel log: the
places you have been, the trips you are planning, and the photos, dates and map
positions that go with them. A composable `kurly.http` workload running the
**backend** image, backed by an external PostgreSQL with PostGIS, with uploaded
photos on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local adventurelog = import 'github.com/metio/kurly/workloads/adventurelog/server.libsonnet';

kurly.list(adventurelog(publicUrl='https://adventurelog.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `adventurelog` | |
| `image` | the pinned backend image | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | `/code/media` |
| `dbHost` / `dbPort` / `database` / `dbUser` | `adventurelog-db-rw` … | pairs with a `cnpg-cluster` named `adventurelog-db` |
| `publicUrl` / `frontendUrl` | `https://adventurelog.example.com` | see below |
| `csrfTrustedOrigins` | `[]` | extra origins, on top of the two above |
| `adminUsername` / `adminEmail` | `admin` / `admin@example.com` | created on first start |
| `disableRegistration` | `false` | |
| `secretName` | `adventurelog` | three credentials, see below |

## The database must have PostGIS

The application is a GeoDjango project: its models carry geometry columns and
its first migration creates the `postgis` extension. A plain PostgreSQL is not
enough — the pod migrates, fails, and restarts forever. Point `dbHost` at a
cluster whose image ships PostGIS.

## publicUrl is not cosmetic

`publicUrl` is the origin a browser reaches this backend at. It is baked into
the media URLs the API hands out and is half of what Django validates
state-changing requests against, so a wrong value shows an application that
loads and then cannot save. `frontendUrl` is where the separate web front end is
served from; both are trusted for CSRF.

The SvelteKit front end is a **different image** and is not carried here. Point
it at this workload's public origin.

## Supply the Secret — every default is published

The project's own compose file ships defaults for all three, the session-signing
key included, so supplying them is the difference between having accounts and
not.

| key | what it protects |
|---|---|
| `POSTGRES_PASSWORD` | the database login |
| `SECRET_KEY` | Django sessions and password-reset tokens |
| `DJANGO_ADMIN_PASSWORD` | the first administrator's account |

```shell
kubectl create secret generic adventurelog \
  --from-literal=POSTGRES_PASSWORD=… \
  --from-literal=DJANGO_ADMIN_PASSWORD=… \
  --from-literal=SECRET_KEY="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
```

## Less hardened, deliberately

`supervisord` runs nginx, memcached and gunicorn together and drops privileges
to their accounts, which it can only do starting from root; nginx also binds
`:80`. The root filesystem is writable because all three keep their pid files,
logs and temporary request bodies inside the image's own tree.

## Slow first start

The first start applies the whole Django migration set, creates the PostGIS
extension and downloads the world region dataset before anything answers, which
takes minutes. That is a long **startup** probe, not a long liveness delay, and
a `StageSet` deploying this needs its `timeout` raised past it.

## Persistence

Uploaded photos live on a ReadWriteOnce volume, so this is **one replica,
recreated** (never rolled). Everything else is in PostgreSQL — point `dbHost` at
one that is backed up.

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
metadata: { name: kurly, namespace: adventurelog }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-adventurelog, namespace: adventurelog }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/adventurelog, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: adventurelog }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-adventurelog, namespace: adventurelog }
spec: { sourceRef: { kind: OCIRepository, name: kurly-adventurelog } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: adventurelog, namespace: adventurelog }
spec:
  serviceAccountName: adventurelog-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/adventurelog/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-adventurelog, importPath: github.com/metio/kurly/workloads/adventurelog }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: adventurelog, namespace: adventurelog }
spec:
  serviceAccountName: adventurelog-deployer
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
        name: adventurelog
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: adventurelog }
```

<!-- END generated: jaas-deploy -->
