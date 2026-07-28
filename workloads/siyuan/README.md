<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# siyuan

[SiYuan](https://github.com/siyuan-note/siyuan) — a privacy-first, self-hosted personal
knowledge-management and note-taking app with block-level editing and a local-first
workspace. A plain composable `kurly.http` workload on the official image; its workspace
(notes, assets and the database) lives on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local siyuan = import 'github.com/metio/kurly/workloads/siyuan/server.libsonnet';
kurly.list(siyuan())
```

SiYuan's web access is gated by an access-auth code — set it through the
`SIYUAN_ACCESS_AUTH_CODE` environment variable (from a Secret via `kurly.envFromSecret`);
kurly authors no Secret. Workspace at `/siyuan/workspace` on a ReadWriteOnce volume, so
**one replica, recreated**. Serves on `:6806`.

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
metadata: { name: kurly, namespace: siyuan }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-siyuan, namespace: siyuan }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/siyuan, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: siyuan }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-siyuan, namespace: siyuan }
spec: { sourceRef: { kind: OCIRepository, name: kurly-siyuan } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: siyuan, namespace: siyuan }
spec:
  serviceAccountName: siyuan-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/siyuan/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-siyuan, importPath: github.com/metio/kurly/workloads/siyuan }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: siyuan, namespace: siyuan }
spec:
  serviceAccountName: siyuan-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: siyuan
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: siyuan }
```

<!-- END generated: jaas-deploy -->
