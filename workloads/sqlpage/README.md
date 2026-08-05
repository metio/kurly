<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# sqlpage

[SQLPage](https://github.com/sqlpage/SQLPage) — build a web application by writing
SQL files. Each `.sql` file is a page, and the rows it returns render as tables,
forms and charts. A plain composable `kurly.http` workload.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local sqlpage = import 'github.com/metio/kurly/workloads/sqlpage/server.libsonnet';

kurly.list(sqlpage(site={
  'index.sql': |||
    select 'text' as component, 'Hello from SQLPage' as contents;
  |||,
}))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `sqlpage` | |
| `image` | `lovasoa/sqlpage:latest` | pinned by digest, see below |
| `site` | `{}` | the `.sql` files — this *is* the app |
| `storageSize` / `storageClass` | `2Gi` / cluster default | `/data` |
| `env` | `{}` | notably `DATABASE_URL` |

## The site is the configuration

SQLPage runs whatever `.sql` files it finds in its web root, so `site` is the
application itself, delivered as a ConfigMap. The files mount **individually**, so
the image's own assets in the web root survive. With no files, SQLPage serves its
built-in welcome page and nothing else.

## Authorisation is your SQL's job

Every page runs with whatever rights `DATABASE_URL` grants, and SQLPage has no
user model of its own. If a page should not be readable by everyone who can reach
it, the SQL has to say so — there is no setting that does it for you.

`DATABASE_URL` defaults to SQLite on the volume rather than the image's own
default, which would place the database **inside the web root** and serve it
alongside the pages. Point it at PostgreSQL or MySQL through `env` for anything
real.

## Pinning, and a warning about the version tags

The pin is `latest@sha256:…` — the digest fixes the bits, which is what
reproducibility needs, while the tag names no version. `latest` was 0.45.0 when
this was written.

That is not laziness. Docker Hub's versioned tags for this repository stop at
`v0.9.5`, and the one tag that looks newer, **`v1.21.2`, contains a completely
different application** — WBO, a whiteboard by the same author, evidently pushed to
the wrong repository. Pinning by version here would have shipped the wrong software
under the right name.

## Persistence

The default SQLite database lives on a ReadWriteOnce volume, so this is **one
replica, recreated** (never rolled). Pointing `DATABASE_URL` at an external
database removes that constraint.

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
metadata: { name: kurly, namespace: sqlpage }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-sqlpage, namespace: sqlpage }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/sqlpage, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: sqlpage }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-sqlpage, namespace: sqlpage }
spec: { sourceRef: { kind: OCIRepository, name: kurly-sqlpage } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: sqlpage, namespace: sqlpage }
spec:
  serviceAccountName: sqlpage-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/sqlpage/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-sqlpage, importPath: github.com/metio/kurly/workloads/sqlpage }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: sqlpage, namespace: sqlpage }
spec:
  serviceAccountName: sqlpage-deployer
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
        name: sqlpage
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: sqlpage }
```

<!-- END generated: jaas-deploy -->
