<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# plex

[Plex Media Server](https://www.plex.tv) — a self-hosted media server for organising and streaming your movies, shows, music and photos. A `kurly.http` workload on the LinuxServer.io image; config on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local plex = import 'github.com/metio/kurly/workloads/plex/server.libsonnet';
kurly.list(plex())
```

Runs as root (s6-overlay), dropping to `puid`/`pgid`. Set `PLEX_CLAIM` (from plex.tv/claim) on first run and mount your media libraries. Config at `/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:32400`.

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
metadata: { name: kurly, namespace: plex }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-plex, namespace: plex }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/plex, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: plex }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-plex, namespace: plex }
spec: { sourceRef: { kind: OCIRepository, name: kurly-plex } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: plex, namespace: plex }
spec:
  serviceAccountName: plex-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/plex/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-plex, importPath: github.com/metio/kurly/workloads/plex }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: plex, namespace: plex }
spec:
  serviceAccountName: plex-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: plex
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: plex }
```

<!-- END generated: jaas-deploy -->
