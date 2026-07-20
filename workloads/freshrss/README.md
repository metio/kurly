<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# freshrss

[FreshRSS](https://github.com/FreshRSS/FreshRSS) — a free, self-hosted RSS and Atom
feed aggregator. A plain composable `kurly.http` workload on the official image: it
keeps its feeds and articles in a SQLite database on a PersistentVolume by default,
so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local freshrss = import 'github.com/metio/kurly/workloads/freshrss/server.libsonnet';

kurly.list(freshrss(baseUrl='https://rss.example.com'))
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `freshrss` | |
| `image` | `docker.io/freshrss/freshrss:1.29.1` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | the SQLite data volume (`/var/www/FreshRSS/data`) |
| `baseUrl` | inferred | the public URL FreshRSS trusts |
| `env` | `{}` | extra environment (`CRON_MIN`, `TZ`, …) |
| `resources` / `labels` / `annotations` | | |

Serves the web app and API on `:80` — compose an exposure onto it. Point it at an
external PostgreSQL/MySQL through the setup wizard to scale past the single SQLite
writer.

## Security and persistence

The Apache + PHP image starts as **root** and binds `:80`, so this workload relaxes
kurly's non-root and read-only-rootfs defaults while keeping dropped capabilities and
no privilege escalation. The SQLite database lives on a ReadWriteOnce volume, so this
is **one replica, recreated**.

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
metadata: { name: kurly, namespace: freshrss }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-freshrss, namespace: freshrss }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/freshrss, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: freshrss }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-freshrss, namespace: freshrss }
spec: { sourceRef: { kind: OCIRepository, name: kurly-freshrss } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: freshrss, namespace: freshrss }
spec:
  serviceAccountName: freshrss-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/freshrss/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-freshrss, importPath: github.com/metio/kurly/workloads/freshrss }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: freshrss, namespace: freshrss }
spec:
  serviceAccountName: freshrss-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: freshrss
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: freshrss }
```

<!-- END generated: jaas-deploy -->
