<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# trip

[TRIP](https://github.com/itskovacs/trip) — a minimalist map tracker and trip
planner: pin the places you care about on a map and plan multi-day itineraries
around them. A plain composable `kurly.http` workload keeping its SQLite
database, configuration, uploaded images and attachments on a PersistentVolume,
so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local trip = import 'github.com/metio/kurly/workloads/trip/server.libsonnet';

kurly.list(trip())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `trip` | |
| `image` | `ghcr.io/itskovacs/trip:1` | |
| `storageSize` / `storageClass` | `5Gi` / cluster default | `/app/storage` |
| `secretName` | none | optional, supplies `SECRET_KEY` and any OIDC credentials |
| `env` / `resources` / `labels` / `annotations` | | |

## Configuration is a file the app writes, and environment variables win

Everything TRIP is configured by lives in one pydantic settings model, read from
`storage/config.env` and overridable per key by an environment variable. The
settings screen writes that file, so a value set through `env` here is the one
that survives an operator changing it in the UI — pick one place and stay there.

```jsonnet
trip(env={ REGISTER_ENABLE: 'false', DEFAULT_CURRENCY: '$' })
```

## The Secret

`SECRET_KEY` signs the tokens users hold. TRIP mints one into
`storage/config.env` on first start when the environment carries none, so a
Secret is optional — but the key then lives on the volume and sessions do not
survive a move to a fresh one. Supplying it pins them:

```shell
kubectl create secret generic trip \
  --from-literal=SECRET_KEY="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
```

The same Secret is the place for `OIDC_CLIENT_SECRET` when you wire single
sign-on.

## Egress: the map does not need it, OIDC does

Map tiles are fetched by the **browser**, not by the pod, so a NetworkPolicy that
allows nothing outbound still leaves the map drawn. Server-side OIDC discovery is
the exception — without egress to the provider, login breaks while everything
else keeps working.

```jsonnet
trip() + kurly.network.kubernetes(allowTo=[{ cidr: '0.0.0.0/0', ports: [443] }])
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
metadata: { name: kurly, namespace: trip }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-trip, namespace: trip }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/trip, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: trip }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-trip, namespace: trip }
spec: { sourceRef: { kind: OCIRepository, name: kurly-trip } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: trip, namespace: trip }
spec:
  serviceAccountName: trip-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/trip/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-trip, importPath: github.com/metio/kurly/workloads/trip }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: trip, namespace: trip }
spec:
  serviceAccountName: trip-deployer
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
        name: trip
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: trip }
```

<!-- END generated: jaas-deploy -->
