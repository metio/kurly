<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# readarr

[Readarr](https://readarr.com) — an ebook and audiobook collection manager for Usenet and BitTorrent users. A `kurly.http` workload on the LinuxServer.io image; application config (SQLite) on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local readarr = import 'github.com/metio/kurly/workloads/readarr/server.libsonnet';
kurly.list(readarr())
```

Config at `/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves the web app and API on `:8787`. Mount your library and download directories and point Readarr at them in its settings.

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
metadata: { name: kurly, namespace: readarr }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-readarr, namespace: readarr }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/readarr, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: readarr }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-readarr, namespace: readarr }
spec: { sourceRef: { kind: OCIRepository, name: kurly-readarr } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: readarr, namespace: readarr }
spec:
  serviceAccountName: readarr-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/readarr/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-readarr, importPath: github.com/metio/kurly/workloads/readarr }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: readarr, namespace: readarr }
spec:
  serviceAccountName: readarr-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: readarr
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: readarr }
```

<!-- END generated: jaas-deploy -->
