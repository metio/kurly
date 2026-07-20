<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# bigcapital

[Bigcapital](https://github.com/bigcapitalhq/bigcapital) — self-hosted accounting
and financial management. Three composable `kurly.http` stages on the official
images: `server` (the API), `webapp` (the front end), and `gateway` (the nginx
entry you expose), backed by external MySQL/MariaDB, MongoDB, and Redis.

## Compose

All three stages must share the same `namePrefix` (default `bigcapital`) and
`secretName` — the gateway reaches the server and webapp by Service names derived
from `namePrefix`. Expose **only the gateway**.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local server = import 'github.com/metio/kurly/workloads/bigcapital/server.libsonnet';
local webapp = import 'github.com/metio/kurly/workloads/bigcapital/webapp.libsonnet';
local gateway = import 'github.com/metio/kurly/workloads/bigcapital/gateway.libsonnet';

kurly.listOf(kurly.join([
  kurly.list(server(baseUrl='https://accounting.example.com')).items,
  kurly.list(webapp()).items,
  kurly.list(gateway()).items,
]))
```

| Stage | Port | Role |
|---|---|---|
| `gateway` | 80 | nginx entry — **expose this**; routes to webapp and `/api` to server |
| `server` | 4000 | the API; needs MySQL, MongoDB, and Redis |
| `webapp` | 80 | the single-page front end (stateless) |

## Databases and secrets

Bigcapital needs **MySQL/MariaDB** (system and per-tenant data), **MongoDB**, and
**Redis**. kurly ships no MySQL or MongoDB recipe — bring your own; Redis can be the
[valkey](../valkey/) workload. The server reads its host coordinates from env and
its passwords and `JWT_SECRET` from a provided Secret via `envFrom`. kurly authors
**no Secret** — fill `bigcapital-secrets` with
[`kurly.externalSecret`](../../main.libsonnet).

## Security

The webapp and gateway are nginx images that start as **root** and bind `:80`, so
those stages relax kurly's non-root and read-only-rootfs defaults while keeping
dropped capabilities and no privilege escalation. The server runs non-root under the
restricted posture.

> Bigcapital's exact environment-variable names evolve across releases — verify the
> `server` env against the version's compose file, and adjust through the `env`
> parameter as needed.

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
metadata: { name: kurly, namespace: bigcapital }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-bigcapital, namespace: bigcapital }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/bigcapital, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: bigcapital }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-bigcapital, namespace: bigcapital }
spec: { sourceRef: { kind: OCIRepository, name: kurly-bigcapital } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: bigcapital-gateway, namespace: bigcapital }
spec:
  serviceAccountName: bigcapital-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local gateway = import 'github.com/metio/kurly/workloads/bigcapital/gateway.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(gateway())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-bigcapital, importPath: github.com/metio/kurly/workloads/bigcapital }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: bigcapital-server, namespace: bigcapital }
spec:
  serviceAccountName: bigcapital-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/bigcapital/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-bigcapital, importPath: github.com/metio/kurly/workloads/bigcapital }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: bigcapital-webapp, namespace: bigcapital }
spec:
  serviceAccountName: bigcapital-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local webapp = import 'github.com/metio/kurly/workloads/bigcapital/webapp.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(webapp())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-bigcapital, importPath: github.com/metio/kurly/workloads/bigcapital }
```

A `StageSet` deploys the stages in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: bigcapital, namespace: bigcapital }
spec:
  serviceAccountName: bigcapital-deployer
  rollbackOnFailure: true
  stages:
    - name: gateway
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: bigcapital-gateway
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: bigcapital-gateway }
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: bigcapital-server
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: bigcapital-server }
    - name: webapp
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: bigcapital-webapp
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: bigcapital-webapp }
```

<!-- END generated: jaas-deploy -->
