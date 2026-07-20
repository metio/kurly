<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# jellyseerr

A Jellyseerr server — a request-management and media-discovery companion for Jellyfin, Emby and Plex, a fork of Overseerr. A plain composable `kurly.http` workload on the official image; its SQLite
configuration and database live on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local jellyseerr = import 'github.com/metio/kurly/workloads/jellyseerr/server.libsonnet';
kurly.list(jellyseerr())
```

Config at `/app/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves
on `:5055`.

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
metadata: { name: kurly, namespace: jellyseerr }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-jellyseerr, namespace: jellyseerr }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/jellyseerr, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: jellyseerr }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-jellyseerr, namespace: jellyseerr }
spec: { sourceRef: { kind: OCIRepository, name: kurly-jellyseerr } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: jellyseerr, namespace: jellyseerr }
spec:
  serviceAccountName: jellyseerr-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/jellyseerr/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-jellyseerr, importPath: github.com/metio/kurly/workloads/jellyseerr }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: jellyseerr, namespace: jellyseerr }
spec:
  serviceAccountName: jellyseerr-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: jellyseerr
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: jellyseerr }
```

<!-- END generated: jaas-deploy -->
