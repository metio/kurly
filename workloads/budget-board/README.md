<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# budget-board

[Budget Board](https://github.com/teelur/budget-board) — personal budgeting:
monthly spending against a budget, net worth over time, and progress towards
savings goals. Two composable `kurly.http` stages, because upstream publishes two
images: `server` (the ASP.NET API) and `client` (the web bundle served by nginx,
which proxies `/api/` to the server). All state lives in an external PostgreSQL.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local server = import 'github.com/metio/kurly/workloads/budget-board/server.libsonnet';
local client = import 'github.com/metio/kurly/workloads/budget-board/client.libsonnet';

kurly.list([
  server(clientAddress='https://budget.example.com'),
  client() + kurly.expose.gateway('budget.example.com', 'public'),
])
```

| Parameter | Default | Notes |
|---|---|---|
| `server.clientAddress` | `http://budget-board-client:6253` | the browser-visible origin of the client |
| `server.dbHost` / `dbPort` / `database` / `dbUser` | `budget-board-db-rw` … | pairs with a `cnpg-cluster` named `budget-board-db` |
| `server.secretName` | `budget-board` | holds `POSTGRES_PASSWORD` |
| `client.serverHost` | `budget-board-server` | the API Service, reached on `:8080` |
| `client.port` | `6253` | what nginx listens on |

## Expose the client, not the API

The browser loads the client and every API call goes through nginx's `/api/`
proxy, so the exposure belongs on the `client` stage. The server takes that same
public origin as `clientAddress`: it is the **only** CORS origin the API allows,
the process refuses to start without one, and a wrong value leaves a web app that
loads perfectly and cannot call anything — the failure is reported by the browser,
not by the server, so nothing in the pod logs says why.

## Supply the Secret

The project's own compose file ships a published default for the database
password, so this is the difference between a database anybody who read the
repository can open and one they cannot:

```shell
kubectl create secret generic budget-board \
  --from-literal=POSTGRES_PASSWORD=…
```

## Persistence and restarts

Neither stage claims a volume: the schema and every row are in PostgreSQL, which
the server migrates as it starts, so point `dbHost` at a database that is backed
up. The API keeps its ASP.NET data-protection keys in an `emptyDir`, which means a
restart signs out whoever is logged in — the alternative would pin the API to one
node for state PostgreSQL already holds.

## Authentication

Local accounts are on by default; `disableNewUsers` closes registration and the
OIDC parameters move sign-in to an external provider. Set the same switches on
both stages, or the login screen offers what the API will refuse.

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
metadata: { name: kurly, namespace: budget-board }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-budget-board, namespace: budget-board }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/budget-board, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: budget-board }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-budget-board, namespace: budget-board }
spec: { sourceRef: { kind: OCIRepository, name: kurly-budget-board } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: budget-board-client, namespace: budget-board }
spec:
  serviceAccountName: budget-board-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local client = import 'github.com/metio/kurly/workloads/budget-board/client.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(client())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-budget-board, importPath: github.com/metio/kurly/workloads/budget-board }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: budget-board-server, namespace: budget-board }
spec:
  serviceAccountName: budget-board-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/budget-board/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-budget-board, importPath: github.com/metio/kurly/workloads/budget-board }
```

A `StageSet` deploys the stages in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: budget-board, namespace: budget-board }
spec:
  serviceAccountName: budget-board-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: client
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: budget-board-client
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: budget-board-client }
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: budget-board-server
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: budget-board-server }
```

<!-- END generated: jaas-deploy -->
