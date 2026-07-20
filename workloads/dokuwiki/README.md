<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# dokuwiki

[DokuWiki](https://www.dokuwiki.org/) — a simple, database-less wiki that stores its
pages as flat files. A plain composable `kurly.http` workload on the official image;
all of its content lives on a PersistentVolume, so it needs no external database.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local dokuwiki = import 'github.com/metio/kurly/workloads/dokuwiki/server.libsonnet';

kurly.list(dokuwiki())
```

| Parameter | Default | Notes |
|---|---|---|
| `name` | `dokuwiki` | |
| `image` | `docker.io/dokuwiki/dokuwiki:2025-05-14b` | |
| `storageSize` / `storageClass` | `2Gi` / cluster default | all content (`/storage`) |
| `env` | `{}` | extra environment |
| `resources` / `labels` / `annotations` | | |

Serves the wiki on `:80` — compose an exposure onto it.

## Security and persistence

The nginx + PHP-FPM image starts as **root** and binds `:80`, so this workload
relaxes kurly's non-root and read-only-rootfs defaults while keeping dropped
capabilities and no privilege escalation. The flat-file content lives on a
ReadWriteOnce volume, so this is **one replica, recreated**.

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
metadata: { name: kurly, namespace: dokuwiki }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-dokuwiki, namespace: dokuwiki }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/dokuwiki, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: dokuwiki }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-dokuwiki, namespace: dokuwiki }
spec: { sourceRef: { kind: OCIRepository, name: kurly-dokuwiki } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: dokuwiki, namespace: dokuwiki }
spec:
  serviceAccountName: dokuwiki-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/dokuwiki/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-dokuwiki, importPath: github.com/metio/kurly/workloads/dokuwiki }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: dokuwiki, namespace: dokuwiki }
spec:
  serviceAccountName: dokuwiki-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: dokuwiki
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: dokuwiki }
```

<!-- END generated: jaas-deploy -->
