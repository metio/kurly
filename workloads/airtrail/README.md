<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# airtrail

[AirTrail](https://github.com/johanohly/AirTrail) — a personal flight log: every
flight you have taken drawn on a world map, with routes, distances, time in the
air and the statistics that fall out of them, importable from the trackers people
already use. A composable `kurly.http` workload backed by an external PostgreSQL,
with uploaded files on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local airtrail = import 'github.com/metio/kurly/workloads/airtrail/server.libsonnet';

kurly.list(airtrail(origin='https://flights.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `airtrail` | |
| `image` | `docker.io/johly/airtrail:v3.11.1` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | `/app/uploads` |
| `origin` | unset | the URL people visit — see below |
| `secretName` | `airtrail` | holds `DB_URL` |
| `bodySizeLimit` | `20M` | flight tracks ride inside the flight form |

## Set `origin`

This is a SvelteKit application, and SvelteKit compares the `Origin` header of
every state-changing request against it. With the image's own default of
`http://localhost:3000` an exposed instance renders pages perfectly and refuses
every sign-in and every saved flight with a CSRF error — a failure that looks
like the application is broken rather than misconfigured.

## Supply the Secret

`DB_URL` is the whole PostgreSQL connection string, so it carries the password
and lives in the Secret rather than being assembled from parameters:

```shell
kubectl create secret generic airtrail \
  --from-literal=DB_URL='postgres://airtrail:…@airtrail-db-rw:5432/airtrail'
```

A `cnpg-cluster` named `airtrail-db` provides that database.

## Persistence

Uploaded files (airline icons and the like) live on a ReadWriteOnce volume, so
this is **one replica, recreated** (never rolled). `UPLOAD_LOCATION` points at
the mount; with no location set the application disables uploads entirely.
Everything else is in PostgreSQL — point `DB_URL` at one that is backed up.

The entrypoint applies migrations before the server listens, so the first boot
against a fresh database takes considerably longer than every later one. That is
what the startup probe budgets for; a `StageSet` deploying this needs a timeout
past it.

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
metadata: { name: kurly, namespace: airtrail }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-airtrail, namespace: airtrail }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/airtrail, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: airtrail }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-airtrail, namespace: airtrail }
spec: { sourceRef: { kind: OCIRepository, name: kurly-airtrail } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: airtrail, namespace: airtrail }
spec:
  serviceAccountName: airtrail-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/airtrail/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-airtrail, importPath: github.com/metio/kurly/workloads/airtrail }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: airtrail, namespace: airtrail }
spec:
  serviceAccountName: airtrail-deployer
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
        name: airtrail
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: airtrail }
```

<!-- END generated: jaas-deploy -->
