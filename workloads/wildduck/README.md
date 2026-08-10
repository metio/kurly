<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# wildduck

[WildDuck](https://wildduck.email/) — an IMAP and POP3 mail server that keeps every
message in MongoDB. A plain composable `kurly.http` workload on the official image,
backed by an external MongoDB and Redis.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local wildduck = import 'github.com/metio/kurly/workloads/wildduck/server.libsonnet';

kurly.list(wildduck(hostname='mail.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `wildduck` | |
| `image` | `ghcr.io/nodemailer/wildduck:1.45.4` | |
| `replicas` | `1` | stateless — scale freely |
| `secretName` | `wildduck` | Secret with the two connection strings and the API token (envFrom) |
| `hostname` | unset | the default domain part for usernames that are not email addresses |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the REST API on `:8080` — compose an exposure onto it. IMAPS (`:9993`) and
POP3S (`:9995`) are **not HTTP**, so no HTTPRoute carries them: route them as TCP
through a `LoadBalancer` Service or a Gateway `TCPRoute`.

## Configuration

WildDuck reads the TOML files shipped in the image, and every value in them can be
overridden by an `APPCONF_<section>_<key>` environment variable. The stage sets the
API host to `0.0.0.0` — the shipped default binds `127.0.0.1`, which neither a probe
nor the Service can reach — and leaves the rest at the image's defaults; add your own
with `env`.

## Databases and secrets

kurly authors **no Secret** — provide one named `wildduck` holding
`APPCONF_dbs_mongo`, `APPCONF_dbs_redis` and `APPCONF_api_accessToken`, pulled in via
`envFrom`. Both connection strings carry a password, which is why they live there
rather than in `env`. Pairs with a [mongodb-cluster](../mongodb-cluster/) named
`wildduck-db` and a Redis-compatible cache.

## Persistence

Mailboxes, messages and attachments live in MongoDB (GridFS), session state in Redis,
so this workload owns **no volume** — a plain rolling Deployment.

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
metadata: { name: kurly, namespace: wildduck }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-wildduck, namespace: wildduck }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/wildduck, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: wildduck }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-wildduck, namespace: wildduck }
spec: { sourceRef: { kind: OCIRepository, name: kurly-wildduck } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: wildduck, namespace: wildduck }
spec:
  serviceAccountName: wildduck-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/wildduck/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-wildduck, importPath: github.com/metio/kurly/workloads/wildduck }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: wildduck, namespace: wildduck }
spec:
  serviceAccountName: wildduck-deployer
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
        name: wildduck
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: wildduck }
```

<!-- END generated: jaas-deploy -->
