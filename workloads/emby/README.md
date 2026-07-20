<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# emby

[Emby](https://emby.media) — a self-hosted media server for streaming your movies, shows, music and photos. A `kurly.http` workload on the LinuxServer.io image; config on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local emby = import 'github.com/metio/kurly/workloads/emby/server.libsonnet';
kurly.list(emby())
```

Runs as root (s6-overlay), dropping to `puid`/`pgid`. Mount your media libraries and add them in the UI. Config at `/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8096`.

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
metadata: { name: kurly, namespace: emby }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-emby, namespace: emby }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/emby, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: emby }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-emby, namespace: emby }
spec: { sourceRef: { kind: OCIRepository, name: kurly-emby } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: emby, namespace: emby }
spec:
  serviceAccountName: emby-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/emby/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-emby, importPath: github.com/metio/kurly/workloads/emby }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: emby, namespace: emby }
spec:
  serviceAccountName: emby-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: emby
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: emby }
```

<!-- END generated: jaas-deploy -->
