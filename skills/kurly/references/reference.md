<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# kurly deploy reference

The full end-to-end wiring for deploying a kurly workload through JaaS and
stageset-controller. This is the shape the Assembler generates; adapt names,
namespace, and features to your environment. For the exact, current API, fetch
<https://kurly.projects.metio.wtf/catalog.json> and the
[reference page](https://kurly.projects.metio.wtf/reference/).

## Why source, not rendered manifests

A stage is a `function(params)` composable app. Rendering it at release time
would bake placeholder defaults no real deployment wants — so kurly publishes its
**Jsonnet source** as single-layer `FROM scratch` OCI images (the library at
`ghcr.io/metio/kurly`, each workload at `ghcr.io/metio/kurly/workloads/<name>`).
The consumer composes their `+` features at *their* render, in JaaS.

## The deploy manifests

```yaml
# 1 — the source images, as Flux OCIRepository sources (selector-less: both are
# single-layer). The library (recipes) and the workload (source).
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: tik }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-tik, namespace: tik }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/tik, ref: { tag: latest } }
---
# 2 — a JsonnetLibrary per source, so the snippet can import each by path.
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: tik }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-tik, namespace: tik }
spec: { sourceRef: { kind: OCIRepository, name: kurly-tik } }
---
# 3 — the snippet: compose the workload with your features; adaptations are TLAs.
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: tik, namespace: tik }
spec:
  serviceAccountName: tik-renderer
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
  libraries:
    - { kind: JsonnetLibrary, name: kurly,     importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-tik, importPath: github.com/metio/kurly/workloads/tik }
  tlas:
    host: ["tik.internal.example.com"]
    storeSize: ["5Gi"]
---
# 4 — stageset applies the rendered output, gated per stage.
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: tik, namespace: tik }
spec:
  serviceAccountName: tik-deployer
  rollbackOnFailure: true
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
```

## Hard-code vs pass-through

Each parameter is either **hard-coded** into the snippet (`kurly.store('/var/lib/tik', '5Gi')`)
or **passed through** as a TLA — threaded into the `function(params)` signature
and supplied by `spec.tlas`. The Assembler toggles between the two per input and
lists exactly which TLAs your snippet must provide.
