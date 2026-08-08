<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# open-quartermaster

[Open QuarterMaster](https://openquartermaster.com/) — an inventory management
system that tracks items across storage blocks, with labels and checkouts. This
workload carries the **core API**, the service everything else in the system talks
to; the base station web interface and the plugins are separate images and are not
carried here. A plain composable `kurly.http` workload on the official image, backed
by an external MongoDB.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local oqm = import 'github.com/metio/kurly/workloads/open-quartermaster/server.libsonnet';

kurly.list(oqm(
  jwtKeyLocation='https://sso.example.com/realms/oqm/protocol/openid-connect/certs',
))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `open-quartermaster` | |
| `image` | `docker.io/ebprod/oqm-core-api:6.2.0` | |
| `replicas` | `2` | stateless — scale freely |
| `port` | `8080` | also written into `QUARKUS_HTTP_PORT` |
| `database` | `oqm` | the MongoDB database |
| `jwtKeyLocation` | unset | the OIDC provider's JWKS URL |
| `events` | `false` | outgoing Kafka messaging |
| `secretName` | `open-quartermaster` | Secret with `QUARKUS_MONGODB_CONNECTION_STRING` (envFrom) |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the REST API on `:8080` — compose an exposure onto it. Pairs with a
[mongodb-cluster](../mongodb-cluster/) named `open-quartermaster-db`.

The Quarkus port is set from the declared port rather than left to the image: the
project's own compose file publishes `:80` while the image's own health check asks
`:8080`, and a Service pointing at the wrong one of those is a workload that never
goes ready.

## Authentication

Every write is behind a bearer token the API verifies against an OIDC provider's
public keys — upstream that is a Keycloak with an `oqm` realm, and kurly carries no
identity provider for it. `jwtKeyLocation` is that JWKS URL. Left unset the API still
starts and still refuses every authenticated call, which is enough to boot and not a
deployment anybody wants.

## Persistence

Items, attached files and audit history all live in MongoDB, so this is **stateless**
— a plain rolling Deployment. The connection string carries the database credentials
and therefore comes from the Secret rather than a parameter.

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
metadata: { name: kurly, namespace: open-quartermaster }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-open-quartermaster, namespace: open-quartermaster }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/open-quartermaster, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: open-quartermaster }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-open-quartermaster, namespace: open-quartermaster }
spec: { sourceRef: { kind: OCIRepository, name: kurly-open-quartermaster } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: open-quartermaster, namespace: open-quartermaster }
spec:
  serviceAccountName: open-quartermaster-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/open-quartermaster/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-open-quartermaster, importPath: github.com/metio/kurly/workloads/open-quartermaster }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: open-quartermaster, namespace: open-quartermaster }
spec:
  serviceAccountName: open-quartermaster-deployer
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
        name: open-quartermaster
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: open-quartermaster }
```

<!-- END generated: jaas-deploy -->
