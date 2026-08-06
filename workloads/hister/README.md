<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# hister

[Hister](https://hister.org/) — a personal web search engine that indexes the
sites you visit, keeps offline previews of them and can search them semantically.
A plain composable `kurly.http` workload on the official image; its index,
previews and configuration file live together on a PersistentVolume, so it needs
no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local hister = import 'github.com/metio/kurly/workloads/hister/server.libsonnet';

kurly.list(
  hister(baseUrl='https://search.example.com')
  + kurly.expose.gateway('search.example.com', 'public')
)
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `hister` | |
| `image` | `ghcr.io/asciimoo/hister:v0.17.0` | |
| `port` | `4433` | |
| `storageSize` / `storageClass` | `10Gi` / cluster default | index, previews and `config.yml` (`/hister/data`) |
| `baseUrl` | unset | the public URL, behind a reverse proxy |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the web app on `:4433` — compose an exposure onto it.

## Listen address

Hister binds a loopback address by default, which neither a probe nor a Service
can reach, so the stage sets `HISTER__SERVER__ADDRESS` to `0.0.0.0` on the
declared port. It also reads `HISTER_PORT` — the very variable Kubernetes injects
for a Service named `hister`, as a `tcp://` URL — so **service links are
disabled**. With them on the address becomes
`0.0.0.0:tcp://<clusterIP>:4433` and the server refuses to listen.

## Configuration

The image points `HISTER_CONFIG` at `/hister/data/config.yml`, on the same volume
as the data. Every setting is therefore either an `HISTER__<SECTION>__<KEY>`
environment variable (pass it through `env`) or an edit to that file. PostgreSQL
instead of the bundled SQLite, semantic search against an OpenAI-compatible
embeddings endpoint, and OAuth logins are all configured that way — none of them
is needed to run.

## Persistence

The index lives on a ReadWriteOnce volume, so this is **one replica, recreated**.

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
metadata: { name: kurly, namespace: hister }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-hister, namespace: hister }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/hister, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: hister }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-hister, namespace: hister }
spec: { sourceRef: { kind: OCIRepository, name: kurly-hister } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: hister, namespace: hister }
spec:
  serviceAccountName: hister-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/hister/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-hister, importPath: github.com/metio/kurly/workloads/hister }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: hister, namespace: hister }
spec:
  serviceAccountName: hister-deployer
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
        name: hister
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: hister }
```

<!-- END generated: jaas-deploy -->
