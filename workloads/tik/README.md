<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# tik workload

The [`tik backend`](https://github.com/metio/tik) supervisor — one process that
serves the read-only board and runs the store's writers (mail ingest, recurring
tickets, dashboards, effects) over a shared append-only event store — as a
composable kurly app.

tik is a **single-stage** workload: its manifests have no install-order
dependency worth gating (the store's PVC binds WaitForFirstConsumer, so it
applies with the pod that consumes it). It ships one stage, `backend`
([`backend.libsonnet`](backend.libsonnet)), plus a version-gated
[migration ladder](migrations.jsonnet).

## 1 · Build the workload

[`backend.libsonnet`](backend.libsonnet) is a **composable app**, not a rendered
List: it imports the kurly library, composes the supervisor with sensible
defaults, and returns the app — with **no exposure** baked in, so you route it
your own way. You adapt it by composing more `+` features, then render with
`kurly.list`:

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local tik = import 'github.com/metio/kurly/workloads/tik/backend.libsonnet';

kurly.list(
  tik()                                              // the workload's composable base
  + kurly.expose.gateway('tik.internal', 'shared-gateway')  // add exposure with your host
  + kurly.store('/var/lib/tik', '5Gi')               // override the store size — any feature
)
```

`+` *is* the parameter system: a workload author never has to enumerate knobs;
the library's features are the parameters, so you can override or add anything.

Render it locally through the flake devShell:

```sh
nix develop --command check-examples   # renders + validates every workload with defaults
```

## 2 · Render it with JaaS

Deploy it in-cluster by making the kurly library and this workload importable as
`JsonnetLibrary`s, then evaluating a `JsonnetSnippet` that composes and renders
the app with your values as TLAs. Both OCI images are **single-layer**, so Flux
pulls them with no `layerSelector` (the JOI/library shape).

```yaml
# The kurly library (recipes) and the tik workload (source) images, from their
# release pipelines. Both single-layer.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: tik }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: tik-workload, namespace: tik }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/tik, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: tik }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: tik-workload, namespace: tik }
spec: { sourceRef: { kind: OCIRepository, name: tik-workload } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: tik, namespace: tik }
spec:
  serviceAccountName: tik-renderer
  # Compose the workload with your environment's features, then render.
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local tik = import 'github.com/metio/kurly/workloads/tik/backend.libsonnet';
      function(host='tik.example.com', storeSize='1Gi')
        kurly.list(
          tik()
          + kurly.expose.gateway(host, 'shared-gateway')
          + kurly.store('/var/lib/tik', storeSize)
        )
  # Both the recipes and the workload source are importable by canonical path.
  libraries:
    - { kind: JsonnetLibrary, name: kurly,        importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: tik-workload,  importPath: github.com/metio/kurly/workloads/tik }
  # Your adaptations, as top-level arguments.
  tlas:
    host: ["tik.internal.example.com"]
    storeSize: ["5Gi"]
```

JaaS publishes the rendered manifests as an `ExternalArtifact`. The workload's
`version` constant was rewritten from `dev` to the release version when the
source was packed, so every object carries `app.kubernetes.io/version`.

## 3 · Deploy it with a StageSet

A `StageSet` deploys the workload's stages in order, pinning artifact revisions
at the start of the run and gating each stage before the next. A stage names the
`JsonnetSnippet` that produced its artifact (the producer-aware reference).

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: tik, namespace: tik }
spec:
  serviceAccountName: tik-deployer   # every apply runs as this tenant SA
  rollbackOnFailure: true            # restore the last-good revision on failure
  stages:
    - name: backend
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: tik
      readyChecks:
        checks:
          - apiVersion: apps/v1
            kind: Deployment
            name: tik
  # The version-gated migration ladder — tik verify / reprocess at boundaries —
  # rendered from migrations.jsonnet by its own snippet.
  migrationsSourceRef:
    apiVersion: jaas.metio.wtf/v1
    kind: JsonnetSnippet
    name: tik-migrations
```
