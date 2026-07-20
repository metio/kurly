<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# nzbhydra2

an NZBHydra2 server — a meta-search server that aggregates Usenet indexers behind one search API for the *arr apps. A `kurly.http` workload on the LinuxServer.io image; config on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local nzbhydra2 = import 'github.com/metio/kurly/workloads/nzbhydra2/server.libsonnet';
kurly.list(nzbhydra2())
```

Runs as root (s6-overlay), dropping to `puid`/`pgid`. Config at `/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:5076`.

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
metadata: { name: kurly, namespace: nzbhydra2 }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-nzbhydra2, namespace: nzbhydra2 }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/nzbhydra2, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: nzbhydra2 }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-nzbhydra2, namespace: nzbhydra2 }
spec: { sourceRef: { kind: OCIRepository, name: kurly-nzbhydra2 } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: nzbhydra2, namespace: nzbhydra2 }
spec:
  serviceAccountName: nzbhydra2-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/nzbhydra2/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-nzbhydra2, importPath: github.com/metio/kurly/workloads/nzbhydra2 }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: nzbhydra2, namespace: nzbhydra2 }
spec:
  serviceAccountName: nzbhydra2-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: nzbhydra2
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: nzbhydra2 }
```

<!-- END generated: jaas-deploy -->
