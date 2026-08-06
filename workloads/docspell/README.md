<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# docspell

[Docspell](https://github.com/eikek/docspell) — files and indexes scanned
documents automatically: it converts what you upload to PDF, runs OCR over it,
guesses the correspondent and the tags from what it has learned so far, and makes
the lot full-text searchable. Two composable stages on the official images, both
backed by the same external PostgreSQL: `server` (the UI and API) and `joex` (the
job executor that does the converting and indexing).

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local server = import 'github.com/metio/kurly/workloads/docspell/server.libsonnet';
local joex = import 'github.com/metio/kurly/workloads/docspell/joex.libsonnet';

kurly.list([
  server(baseUrl='https://docs.example.com') + kurly.expose.ingress('docs.example.com'),
  joex(),
])
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `docspell` / `docspell-joex` | |
| `baseUrl` | — / `http://docspell-joex:7878` | the server's public URL; joex's own Service |
| `jdbcUrl` / `dbUser` | `jdbc:postgresql://docspell-db-rw:5432/docspell` … | pairs with a `cnpg-cluster` named `docspell-db` |
| `signupMode` | `open` | server only — see below |
| `appId` / `poolSize` | `joex1` / `1` | joex only |
| `secretName` | `docspell` | the database password, see below |

## Run both stages

The server only queues work. Every upload is converted, OCR'd and indexed by a
joex node, so a deployment without one accepts documents and quietly processes
none of them — they sit in the queue looking like a stuck upload.

joex is an HTTP workload rather than a worker because it is *addressed*: a node
registers its own base URL in the database and the server calls back to it to
cancel a job or ask what it is doing. `baseUrl` must therefore resolve to this
stage's own Service. Do not expose it — nothing outside the namespace calls it.

Docspell identifies a job executor by its `app-id`, so a second node means
rendering the joex stage again with a different `name` and `appId`, not raising
`replicas`.

## Supply the Secret

Both stages read the database password from a Secret via `envFrom`, under the
name each component's own config key maps to:

| key | read by |
|---|---|
| `DOCSPELL_SERVER_BACKEND_JDBC_PASSWORD` | `server` |
| `DOCSPELL_JOEX_JDBC_PASSWORD` | `joex` |

One Secret holding both keys serves both stages — the extra key each does not
read is harmless.

```shell
kubectl create secret generic docspell \
  --from-literal=DOCSPELL_SERVER_BACKEND_JDBC_PASSWORD=… \
  --from-literal=DOCSPELL_JOEX_JDBC_PASSWORD=…
```

## Signup is open by default

`signupMode` carries Docspell's own default, `open`: anybody who can reach the URL
can create an account and start uploading. Decide between `open`, `invite` and
`closed` *before* composing an exposure onto the server.

## Configuration is entirely environment

Docspell maps a config key onto an environment variable by uppercasing it and
turning a dot into `_` and a dash into `__`, so `docspell.server.backend.jdbc.url`
becomes `DOCSPELL_SERVER_BACKEND_JDBC_URL`. The images delete their bundled config
file, so anything not set here is the built-in default — including the bind
address, which is `localhost` upstream and set explicitly to `0.0.0.0` here
because in a pod the default binds where neither the probe nor the Service can
reach it. Pass anything else through `env`.

## Persistence

Neither stage claims a volume. Documents themselves live in PostgreSQL by
default, so the database is the whole of the state — point `jdbcUrl` at one that
is backed up. joex's `/tmp` is a scratch volume sized for conversions; raise its
limit if large scans fill it.

Full-text search is off unless a Solr is configured. Without it Docspell still
searches metadata, so it is a real deployment, not a broken one.

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
metadata: { name: kurly, namespace: docspell }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-docspell, namespace: docspell }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/docspell, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: docspell }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-docspell, namespace: docspell }
spec: { sourceRef: { kind: OCIRepository, name: kurly-docspell } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: docspell-joex, namespace: docspell }
spec:
  serviceAccountName: docspell-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local joex = import 'github.com/metio/kurly/workloads/docspell/joex.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(joex())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-docspell, importPath: github.com/metio/kurly/workloads/docspell }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: docspell-server, namespace: docspell }
spec:
  serviceAccountName: docspell-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/docspell/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-docspell, importPath: github.com/metio/kurly/workloads/docspell }
```

A `StageSet` deploys the stages in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: docspell, namespace: docspell }
spec:
  serviceAccountName: docspell-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: joex
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: docspell-joex
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: docspell-joex }
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: docspell-server
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: docspell-server }
```

<!-- END generated: jaas-deploy -->
