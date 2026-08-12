<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# parse-server

[Parse Server](https://parseplatform.org) — a backend-as-a-service: a REST and
GraphQL API over a document store, with users, sessions, files, push
notifications and cloud functions. A plain composable `kurly.http` workload: all
state is in the external database, so it claims no volume and scales
horizontally.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local parse = import 'github.com/metio/kurly/workloads/parse-server/server.libsonnet';

kurly.list(parse(
  secretName='parse-server',
  serverUrl='https://api.example.com/parse',
))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `parse-server` | |
| `image` | the pinned upstream image | |
| `replicas` | `1` | stateless, so scale freely |
| `appId` | `parse` | the application id clients send; not a secret |
| `serverUrl` | `http://parse-server:1337/parse` | the URL clients reach this at |
| `mountPath` | `/parse` | the path the API is served under |
| `secretName` | none | `PARSE_SERVER_MASTER_KEY` and `PARSE_SERVER_DATABASE_URI` |
| `env` | `{}` | any other `PARSE_SERVER_*` setting |
| `resources` / `labels` / `annotations` | | |

Serves the API on `:1337` — compose an exposure onto it.

## The master key is the whole security model

A request carrying it bypasses every class-level permission and ACL Parse
enforces. It belongs in the Secret, is never shipped to a client, and cannot be
rotated without updating everything that holds it.

```shell
kubectl create secret generic parse-server \
  --from-literal=PARSE_SERVER_MASTER_KEY="$(openssl rand -hex 32)" \
  --from-literal=PARSE_SERVER_DATABASE_URI='mongodb://parse:…@parse-db:27017/parse'
```

## Server URL

`serverUrl` is the address Parse hands to clients and writes into the links in
the files and password-reset mails it generates. It has to be the URL a client
actually reaches, including the mount path — a value that is right for the
cluster and wrong for the internet produces working API calls and broken file
downloads.

The default file adapter writes into the database (GridFS on MongoDB), which is
why this needs no volume. A deployment storing many large files wants an S3 file
adapter configured through `env` instead.

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
metadata: { name: kurly, namespace: parse-server }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-parse-server, namespace: parse-server }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/parse-server, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: parse-server }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-parse-server, namespace: parse-server }
spec: { sourceRef: { kind: OCIRepository, name: kurly-parse-server } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: parse-server, namespace: parse-server }
spec:
  serviceAccountName: parse-server-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/parse-server/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-parse-server, importPath: github.com/metio/kurly/workloads/parse-server }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: parse-server, namespace: parse-server }
spec:
  serviceAccountName: parse-server-deployer
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
        name: parse-server
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: parse-server }
```

<!-- END generated: jaas-deploy -->
