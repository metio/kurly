<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# lobe-chat

[LobeChat](https://github.com/lobehub/lobe-chat) — a self-hosted, open-source AI chat UI supporting many LLM providers, plugins and multimodal input. A `kurly.http` workload on the official image. In its default mode conversations are stored client-side, so the server holds no data.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local lobechat = import 'github.com/metio/kurly/workloads/lobe-chat/server.libsonnet';
kurly.list(lobechat())
```

Stateless — a plain, horizontally scalable Deployment. Serves on `:3210`.

**Providers:** point LobeChat at your LLM providers with the documented environment variables. kurly authors no Secret; pass non-secret settings via `env` and provide API keys through a Secret (compose `kurly.envFromSecret` on).

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
metadata: { name: kurly, namespace: lobe-chat }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-lobe-chat, namespace: lobe-chat }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/lobe-chat, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: lobe-chat }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-lobe-chat, namespace: lobe-chat }
spec: { sourceRef: { kind: OCIRepository, name: kurly-lobe-chat } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: lobe-chat, namespace: lobe-chat }
spec:
  serviceAccountName: lobe-chat-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/lobe-chat/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-lobe-chat, importPath: github.com/metio/kurly/workloads/lobe-chat }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: lobe-chat, namespace: lobe-chat }
spec:
  serviceAccountName: lobe-chat-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: lobe-chat
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: lobe-chat }
```

<!-- END generated: jaas-deploy -->
