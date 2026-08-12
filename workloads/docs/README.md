<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# docs

[Docs](https://github.com/suitenumerique/docs) — collaborative note-taking and
wiki, incubated by France's DINUM and now a recognised Digital Public Good. Three
composable stages.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local backend = import 'github.com/metio/kurly/workloads/docs/backend.libsonnet';
local frontend = import 'github.com/metio/kurly/workloads/docs/frontend.libsonnet';
local yprovider = import 'github.com/metio/kurly/workloads/docs/y-provider.libsonnet';

kurly.list([
  backend(publicUrl='docs.example.com'),
  frontend(),
  yprovider(),
])
```

| Stage | Kind | Serves |
|---|---|---|
| `frontend` | http | the application, `:8080` — expose **this** one |
| `backend` | http | the Django API, `:8000` |
| `y-provider` | http | collaboration over WebSocket, `:4444` |

## Each one matters

Without `y-provider` a deployment looks like it works until two people open the
same document — then each sees only their own typing, with nothing in a log to
explain it. Documents still open and save through the backend, so the failure is
invisible until somebody collaborates.

Route `/api` and `/collaboration` to the backend and y-provider through the same
origin as the frontend; the browser talks to all three.

## Sign-in goes through an external provider

Docs authenticates over OIDC and has no local accounts, so without a provider
configured nobody can sign in at all. `DJANGO_SECRET_KEY` signs the session
cookie — a value that changes on restart signs everybody out — and y-provider and
the backend authenticate each other with a shared secret, so both stages must read
the same Secret.

## Attachments go to object storage

Not to a volume, which is why no stage claims one. kurly carries `seaweedfs`,
`garagehq` and `zenko-cloudserver` for that.

y-provider holds the in-flight document in memory and hands the result to the
backend, so it runs as one replica: two would hold different copies of the same
page.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**rendered** — this workload renders and validates against the Kubernetes schemas with its defaults.

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
metadata: { name: kurly, namespace: docs }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: 2026.7.29 } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-docs, namespace: docs }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/docs, ref: { tag: 2026.7.29 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: docs }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-docs, namespace: docs }
spec: { sourceRef: { kind: OCIRepository, name: kurly-docs } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: docs-backend, namespace: docs }
spec:
  serviceAccountName: docs-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local backend = import 'github.com/metio/kurly/workloads/docs/backend.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(backend())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-docs, importPath: github.com/metio/kurly/workloads/docs }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: docs-frontend, namespace: docs }
spec:
  serviceAccountName: docs-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local frontend = import 'github.com/metio/kurly/workloads/docs/frontend.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(frontend())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-docs, importPath: github.com/metio/kurly/workloads/docs }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: docs-y-provider, namespace: docs }
spec:
  serviceAccountName: docs-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local y_provider = import 'github.com/metio/kurly/workloads/docs/y-provider.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(y_provider())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-docs, importPath: github.com/metio/kurly/workloads/docs }
```

A `StageSet` deploys the stages in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: docs, namespace: docs }
spec:
  serviceAccountName: docs-deployer
  rollbackOnFailure: true
  # stageset gives a stage FIVE MINUTES unless told otherwise, which is shorter
  # than a first deploy takes for anything that migrates a database before it
  # serves. Paired with rollbackOnFailure that is not merely a failed check: the
  # stage is rolled back mid-migration, the retry starts over, and it never
  # converges. Raise it past the startup budget the workload itself allows.
  timeout: 15m
  stages:
    - name: backend
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: docs-backend
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: docs-backend }
    - name: frontend
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: docs-frontend
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: docs-frontend }
    - name: y-provider
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: docs-y-provider
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: docs-y-provider }
```

<!-- END generated: jaas-deploy -->
