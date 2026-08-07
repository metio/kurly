<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# shipshipship

[ShipShipShip](https://github.com/GauthierNelkinsky/ShipShipShip) — a public
changelog and roadmap page for telling customers what shipped, what is being
worked on and what is planned, edited from a Kanban board behind an admin login.
A plain composable `kurly.http` workload keeping its SQLite database, uploads and
installed themes on a PersistentVolume.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local shipshipship = import 'github.com/metio/kurly/workloads/shipshipship/server.libsonnet';

kurly.list(shipshipship())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `shipshipship` | |
| `image` | `docker.io/nelkinsky/shipshipship:v1.3.5` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | `/app/data` |
| `baseUrl` | unset | the address the site is reached at, for newsletter links |
| `secretName` | `shipshipship` | `ADMIN_USERNAME`, `ADMIN_PASSWORD`, `JWT_SECRET` |
| `env` / `resources` / `labels` / `annotations` | | |

## The Secret

The image ships a published `JWT_SECRET`, and that token signs the admin session.
Supplying your own is not hardening, it is the difference between an admin login
only you can mint and one anybody who read the source can:

```shell
kubectl create secret generic shipshipship \
  --from-literal=ADMIN_USERNAME=admin \
  --from-literal=ADMIN_PASSWORD="$(head -c 24 /dev/urandom | base64)" \
  --from-literal=JWT_SECRET="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
```

## Everything is public except `/admin`

The changelog is the product: the whole surface is meant to be read by anyone,
and only `/admin` asks for credentials. Compose the exposure accordingly — this
is not a workload to put behind an authenticating proxy wholesale, or customers
cannot read what you shipped.

## `baseUrl` only matters if you send mail

Newsletter mails build their links from it. There is no default that is right
anywhere, so it stays unset; the site itself works without it and the mails
simply carry no working link.

## Persistence

The SQLite database, uploaded images and any theme installed through the admin
interface all live under `/app/data` on **one ReadWriteOnce volume, so one
replica, recreated** (never rolled).

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
metadata: { name: kurly, namespace: shipshipship }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-shipshipship, namespace: shipshipship }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/shipshipship, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: shipshipship }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-shipshipship, namespace: shipshipship }
spec: { sourceRef: { kind: OCIRepository, name: kurly-shipshipship } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: shipshipship, namespace: shipshipship }
spec:
  serviceAccountName: shipshipship-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/shipshipship/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-shipshipship, importPath: github.com/metio/kurly/workloads/shipshipship }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: shipshipship, namespace: shipshipship }
spec:
  serviceAccountName: shipshipship-deployer
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
        name: shipshipship
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: shipshipship }
```

<!-- END generated: jaas-deploy -->
