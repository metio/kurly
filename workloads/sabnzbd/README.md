<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# sabnzbd

a SABnzbd server — a self-hosted, web-based binary newsreader (Usenet downloader). A plain composable `kurly.http` workload on the LinuxServer.io image; its
config (SQLite) lives on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local sabnzbd = import 'github.com/metio/kurly/workloads/sabnzbd/server.libsonnet';
kurly.list(sabnzbd())
```

The LinuxServer.io s6-overlay init runs as root and drops to `puid`/`pgid`, so this runs
as root with a writable root filesystem (kurly keeps the rest of the hardening). Config at
`/config` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8080`.

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
metadata: { name: kurly, namespace: sabnzbd }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-sabnzbd, namespace: sabnzbd }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/sabnzbd, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: sabnzbd }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-sabnzbd, namespace: sabnzbd }
spec: { sourceRef: { kind: OCIRepository, name: kurly-sabnzbd } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: sabnzbd, namespace: sabnzbd }
spec:
  serviceAccountName: sabnzbd-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/sabnzbd/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-sabnzbd, importPath: github.com/metio/kurly/workloads/sabnzbd }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: sabnzbd, namespace: sabnzbd }
spec:
  serviceAccountName: sabnzbd-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: sabnzbd
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: sabnzbd }
```

<!-- END generated: jaas-deploy -->
