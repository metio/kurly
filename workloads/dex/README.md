<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# dex

[Dex](https://dexidp.io/) — an OpenID Connect / OAuth 2.0 identity provider that
federates to upstream connectors (LDAP, SAML, GitHub, Google, …). A plain composable
`kurly.http` workload on the official image: with the SQLite storage backend its
state lives on a PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local dex = import 'github.com/metio/kurly/workloads/dex/server.libsonnet';

kurly.list(dex())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `dex` | |
| `image` | `ghcr.io/dexidp/dex:v2.45.1` | |
| `storageSize` / `storageClass` | `1Gi` / cluster default | the SQLite state (`/var/dex`) |
| `configSecret` | `dex-config` | Secret holding `config.yaml`, mounted at `/etc/dex` |
| `env` / `resources` / `labels` / `annotations` | | |

Serves the OIDC endpoints on `:5556` — compose an exposure onto it.

## Configuration

Dex is entirely driven by a `config.yaml` (issuer, storage, connectors,
`staticClients`). It carries secrets (client secrets, connector credentials), so
mount it from a Secret — kurly authors **none** — at `/etc/dex`. The default storage
is SQLite on the volume; point it at PostgreSQL in the config to scale past the single
writer, or use the `kubernetes` storage backend composed with `kurly.rbac`.

## Persistence

With SQLite storage, the database lives on a ReadWriteOnce volume, so this is **one
replica, recreated** — the same single-writer discipline as
[vaultwarden](../vaultwarden/).

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
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: dex }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-dex, namespace: dex }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/dex, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: dex }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-dex, namespace: dex }
spec: { sourceRef: { kind: OCIRepository, name: kurly-dex } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: dex, namespace: dex }
spec:
  serviceAccountName: dex-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/dex/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-dex, importPath: github.com/metio/kurly/workloads/dex }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: dex, namespace: dex }
spec:
  serviceAccountName: dex-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: dex
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: dex }
```

<!-- END generated: jaas-deploy -->
