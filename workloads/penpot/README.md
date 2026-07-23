<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# penpot

[Penpot](https://penpot.app) — the self-hosted, open-source design and prototyping platform, an
alternative to Figma. It runs as **three workloads** — a `backend` (API + data), a `frontend`
(the nginx-served web app that proxies to the others), and an `exporter` (headless-browser
rendering) — backed by an external PostgreSQL and Redis.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local backend = import 'github.com/metio/kurly/workloads/penpot/backend.libsonnet';
local frontend = import 'github.com/metio/kurly/workloads/penpot/frontend.libsonnet';
local exporter = import 'github.com/metio/kurly/workloads/penpot/exporter.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.list([
  cnpg(name='penpot-db', database='penpot'),
  backend(),
  frontend(),
  exporter(),
])
```

All three stages share a Secret (`penpot-secrets`) via `envFrom` holding the PostgreSQL/Redis
connection and `PENPOT_SECRET_KEY` — kurly authors **no Secret**. The **frontend** is the
user-facing stage on `:80` and reaches the backend/exporter by their Service names; the backend
serves the API on `:6060` with uploaded assets on a ReadWriteOnce volume (one replica, recreated —
or put assets on S3 to scale out); the exporter serves on `:6061`.

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
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: penpot }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-penpot, namespace: penpot }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/penpot, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: penpot }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-penpot, namespace: penpot }
spec: { sourceRef: { kind: OCIRepository, name: kurly-penpot } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: penpot-backend, namespace: penpot }
spec:
  serviceAccountName: penpot-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local backend = import 'github.com/metio/kurly/workloads/penpot/backend.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(backend())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-penpot, importPath: github.com/metio/kurly/workloads/penpot }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: penpot-exporter, namespace: penpot }
spec:
  serviceAccountName: penpot-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local exporter = import 'github.com/metio/kurly/workloads/penpot/exporter.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(exporter())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-penpot, importPath: github.com/metio/kurly/workloads/penpot }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: penpot-frontend, namespace: penpot }
spec:
  serviceAccountName: penpot-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local frontend = import 'github.com/metio/kurly/workloads/penpot/frontend.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(frontend())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-penpot, importPath: github.com/metio/kurly/workloads/penpot }
```

A `StageSet` deploys the stages in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: penpot, namespace: penpot }
spec:
  serviceAccountName: penpot-deployer
  rollbackOnFailure: true
  stages:
    - name: backend
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: penpot-backend
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: penpot-backend }
    - name: exporter
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: penpot-exporter
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: penpot-exporter }
    - name: frontend
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: penpot-frontend
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: penpot-frontend }
```

<!-- END generated: jaas-deploy -->
