<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# teslamate

[TeslaMate](https://github.com/teslamate-org/teslamate) — logs a Tesla's drives,
charges and state of charge into PostgreSQL and reports efficiency, cost and
mileage from it. A plain composable `kurly.http` workload backed by an external
PostgreSQL; the pod itself keeps nothing.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local teslamate = import 'github.com/metio/kurly/workloads/teslamate/server.libsonnet';

kurly.list(teslamate())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `teslamate` | |
| `image` | `docker.io/teslamate/teslamate:4.1.1` | |
| `dbHost` / `dbPort` / `database` / `dbUser` | `teslamate-db-rw` … | pairs with a `cnpg-cluster` named `teslamate-db` |
| `secretName` | `teslamate` | two keys, see below |
| `mqttHost` | `null` | unset publishes nothing and sets `DISABLE_MQTT` |
| `timezone` | `UTC` | drives and reports are rendered in this zone |

## There are no accounts

The web app authenticates nobody. Anyone who reaches it can read where the car
has been and change its sleep settings, so any exposure that leaves the cluster
belongs behind an authenticating proxy.

## Supply the Secret

```shell
kubectl create secret generic teslamate \
  --from-literal=DATABASE_PASS=… \
  --from-literal=ENCRYPTION_KEY="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
```

`ENCRYPTION_KEY` encrypts the stored Tesla API tokens. Change it and the saved
credentials can no longer be read — the car has to be signed in again — so pick
it once, before the first deploy, and keep it.

## The dashboards are separate software

TeslaMate publishes Grafana dashboards that read the same database. This
workload is the logger; point a Grafana at `database` to get the graphs.

## Persistence

Everything recorded lives in PostgreSQL, so this workload claims no volume —
point `dbHost` at a database that is backed up. The root filesystem is writable
because the Erlang release generates its start-up files and caches elevation
data inside its own install tree.

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
metadata: { name: kurly, namespace: teslamate }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-teslamate, namespace: teslamate }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/teslamate, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: teslamate }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-teslamate, namespace: teslamate }
spec: { sourceRef: { kind: OCIRepository, name: kurly-teslamate } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: teslamate, namespace: teslamate }
spec:
  serviceAccountName: teslamate-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/teslamate/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-teslamate, importPath: github.com/metio/kurly/workloads/teslamate }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: teslamate, namespace: teslamate }
spec:
  serviceAccountName: teslamate-deployer
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
        name: teslamate
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: teslamate }
```

<!-- END generated: jaas-deploy -->
