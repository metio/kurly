<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# flame

[Flame](https://github.com/pawelmalak/flame) — a self-hosted, minimalist start page and
application/bookmark dashboard for your homelab, with a built-in editor. A plain composable
`kurly.http` workload on the official image; its SQLite database lives on a
PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local flame = import 'github.com/metio/kurly/workloads/flame/server.libsonnet';
kurly.list(flame())
```

Set the admin password through the `PASSWORD` environment variable (from a Secret via
`kurly.envFromSecret`); kurly authors **no Secret**. Data at `/app/data` on a ReadWriteOnce
volume, so **one replica, recreated**. Serves on `:5005`.

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
metadata: { name: kurly, namespace: flame }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-flame, namespace: flame }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/flame, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: flame }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-flame, namespace: flame }
spec: { sourceRef: { kind: OCIRepository, name: kurly-flame } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: flame, namespace: flame }
spec:
  serviceAccountName: flame-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/flame/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-flame, importPath: github.com/metio/kurly/workloads/flame }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: flame, namespace: flame }
spec:
  serviceAccountName: flame-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: flame
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: flame }
```

<!-- END generated: jaas-deploy -->
