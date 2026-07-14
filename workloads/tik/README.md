<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# tik workload

The [`tik backend`](https://github.com/metio/tik) supervisor — one process that
serves the read-only board and runs the store's writers (mail ingest, recurring
tickets, dashboards, effects) over a shared append-only event store — declared
with kurly's composable `+` features.

tik is a **single-stage** workload: its manifests have no install-order
dependency worth gating (the store's PVC binds WaitForFirstConsumer, so it
applies with the pod that consumes it, and the HTTPRoute simply has no endpoints
until the board is ready). It ships one rollout stage, `backend`, plus a
version-gated [migration ladder](migrations.jsonnet).

## 1 · Build the workload

[`stages.jsonnet`](stages.jsonnet) imports the kurly library and composes the
supervisor. It is a `function(params)` so JaaS can render it with your own
values; the artifact pipeline renders the defaults.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';

function(image='ghcr.io/metio/tik:2026.7.14174051', host='tik.example.com', storeSize='1Gi')
  local tik =
    kurly.http('tik', image)
    + kurly.replicas(1)                        // one supervisor: a single writer
    + kurly.recreate()                         // ReadWriteOnce store — never roll
    + kurly.port(7777)
    + kurly.args(['backend', '--config=/etc/tik/pipelines.edn'])
    + kurly.env({ TIK_ROOT: '/var/lib/tik', TIK_KEY: '/etc/tik-key/id_ed25519' })
    + kurly.store('/var/lib/tik', storeSize)
    + kurly.config({ 'pipelines.edn': pipelines }, mountPath='/etc/tik')
    + kurly.secretMount('tik-signing-key', '/etc/tik-key', optional=true, defaultMode=256)
    + kurly.scratch('/tmp', '64Mi')
    + kurly.runAs(12345)
    + kurly.probes('/tickets.edn')
    + kurly.expose.gateway(host, 'shared-gateway', gatewayNamespace='infrastructure');
  { backend: kurly.list(tik) }
```

Render it locally through the flake devShell (`jb install` vendors k8s-libsonnet):

```sh
nix develop --command bash -c 'jb install && jsonnet -J vendor workloads/tik/stages.jsonnet'
```

The published artifact is `ghcr.io/metio/kurly/workloads/tik`, one OCI layer per
stage plus the migration ladder — see [Deploy without JaaS](#deploy-without-jaas).

## 2 · Render it with JaaS

To render the workload **in-cluster with your own parameters**, make kurly
importable as a `JsonnetLibrary` and evaluate a `JsonnetSnippet` that composes
the workload with your values as TLAs. JaaS publishes the result as an
`ExternalArtifact` that stageset consumes.

All of kurly's *recipes* are one library, so they publish as **one image and one
`JsonnetLibrary`** — the single-layer `ghcr.io/metio/kurly` image the release
pipeline builds (`:latest` plus dated calver tags; pin a dated tag for
reproducibility). This is distinct from the *workload* image
(`ghcr.io/metio/kurly/workloads/tik`, one per workload — see
[Deploy without JaaS](#deploy-without-jaas)): here we import the recipes to
render tik ourselves, rather than pull tik's pre-rendered manifests.

```yaml
# The kurly library image from kurly's release pipeline, pulled by Flux.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: kurly
  namespace: tik
spec:
  interval: 12h
  url: oci://ghcr.io/metio/kurly
  ref:
    tag: latest   # or a dated tag, e.g. 2026.7.20143022, to pin a revision
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata:
  name: kurly
  namespace: tik
spec:
  sourceRef:
    kind: OCIRepository
    name: kurly
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata:
  name: tik
  namespace: tik
spec:
  serviceAccountName: tik-renderer
  # The composition, importing kurly by its library import path. This is the
  # same shape as stages.jsonnet, with the library path in place of the repo's
  # relative import.
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      function(host='tik.example.com', storeSize='1Gi')
        { backend: kurly.list(
            kurly.http('tik', 'ghcr.io/metio/tik:2026.7.14174051')
            + kurly.replicas(1) + kurly.recreate() + kurly.port(7777)
            + kurly.args(['backend', '--config=/etc/tik/pipelines.edn'])
            + kurly.store('/var/lib/tik', storeSize)
            + kurly.expose.gateway(host, 'shared-gateway')) }
  # Make the kurly library importable under the path used above.
  libraries:
    - kind: JsonnetLibrary
      name: kurly
      importPath: github.com/metio/kurly
  # Your adaptations, passed as top-level arguments to the function.
  tlas:
    host: ["tik.internal.example.com"]
    storeSize: ["5Gi"]
```

## 3 · Deploy it with a StageSet

A `StageSet` deploys the workload's stages in order, pinning artifact revisions
at the start of the run and gating each stage before the next. A stage names the
`JsonnetSnippet` that produced its artifact (the producer-aware reference);
stageset resolves the snippet's `ExternalArtifact` and applies it.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata:
  name: tik
  namespace: tik
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
  # The version-gated migration ladder — tik verify / reprocess at boundaries.
  migrationsSourceRef:
    apiVersion: jaas.metio.wtf/v1
    kind: JsonnetSnippet
    name: tik
```

## Deploy without JaaS

If you don't need per-cluster parameters, skip the snippet and point Flux
straight at the pre-rendered workload artifact — one layer per stage, selected
by media type:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: tik-backend
  namespace: tik
spec:
  interval: 12h
  url: oci://ghcr.io/metio/kurly/workloads/tik
  ref:
    tag: latest
  layerSelector:
    mediaType: application/vnd.metio.stage.backend.tar+gzip
    operation: extract
```

and reference that `OCIRepository` from the StageSet stage's `sourceRef`
(`kind: OCIRepository`) instead of the `JsonnetSnippet`. The migration ladder
rides the `application/vnd.metio.migrations.tar+gzip` layer.
