<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# radicale

[Radicale](https://radicale.org/) — a lightweight CalDAV and CardDAV server for
calendars and contacts. A plain composable `kurly.http` workload on the
well-maintained [tomsquest](https://github.com/tomsquest/docker-radicale) image
that keeps its collections on a PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local radicale = import 'github.com/metio/kurly/workloads/radicale/server.libsonnet';

kurly.list(radicale())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `radicale` | |
| `image` | `docker.io/tomsquest/docker-radicale:3.7.6.0` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the collections volume (`/data`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves CalDAV/CardDAV on `:5232` — compose an exposure onto it:

```jsonnet
kurly.list([
  radicale()
  + kurly.expose.ownGateway('dav.example.com', 'istio', tls='radicale-tls'),
  kurly.certificate('radicale-tls', ['dav.example.com'], 'letsencrypt-prod'),
])
```

## Authentication

The default configuration allows **anonymous access**. For real use, mount a
Radicale config and an htpasswd users file (a Secret — kurly mints none) and set
`auth` to `htpasswd`:

```jsonnet
radicale()
+ kurly.config('/config', { config: '[auth]\ntype = htpasswd\nhtpasswd_filename = /config/users\nhtpasswd_encryption = bcrypt\n' })
+ kurly.secretMount('radicale-users', '/config/users-secret')
```

## Security and persistence

The image runs its s6 init as its designated **uid 2999** and writes to the root
filesystem, so this workload pins that uid and relaxes the read-only-rootfs default
while keeping non-root, dropped capabilities, and no privilege escalation. The
collections live on a ReadWriteOnce volume, so this is **one replica, recreated**.

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
metadata: { name: kurly, namespace: radicale }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-radicale, namespace: radicale }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/radicale, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: radicale }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-radicale, namespace: radicale }
spec: { sourceRef: { kind: OCIRepository, name: kurly-radicale } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: radicale, namespace: radicale }
spec:
  serviceAccountName: radicale-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/radicale/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-radicale, importPath: github.com/metio/kurly/workloads/radicale }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: radicale, namespace: radicale }
spec:
  serviceAccountName: radicale-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: radicale
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: radicale }
```

<!-- END generated: jaas-deploy -->
