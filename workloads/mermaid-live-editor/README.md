<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# mermaid-live-editor

[Mermaid Live Editor](https://github.com/mermaid-js/mermaid-live-editor) — a self-hosted, in-browser editor for Mermaid diagrams (flowcharts, sequence diagrams, Gantt charts and more from text). A `kurly.http` workload on the official image. Diagrams are rendered client-side and shared via URL, so the server only serves static assets and holds no data.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local mermaid = import 'github.com/metio/kurly/workloads/mermaid-live-editor/server.libsonnet';
kurly.list(mermaid())
```

Stateless — a plain, horizontally scalable Deployment. Serves on `:8080`.

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
metadata: { name: kurly, namespace: mermaid-live-editor }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-mermaid-live-editor, namespace: mermaid-live-editor }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/mermaid-live-editor, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: mermaid-live-editor }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-mermaid-live-editor, namespace: mermaid-live-editor }
spec: { sourceRef: { kind: OCIRepository, name: kurly-mermaid-live-editor } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: mermaid-live-editor, namespace: mermaid-live-editor }
spec:
  serviceAccountName: mermaid-live-editor-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/mermaid-live-editor/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-mermaid-live-editor, importPath: github.com/metio/kurly/workloads/mermaid-live-editor }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: mermaid-live-editor, namespace: mermaid-live-editor }
spec:
  serviceAccountName: mermaid-live-editor-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: mermaid-live-editor
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: mermaid-live-editor }
```

<!-- END generated: jaas-deploy -->
