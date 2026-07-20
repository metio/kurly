<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# anythingllm

[AnythingLLM](https://anythingllm.com) — a self-hosted, all-in-one AI application: chat with your documents through RAG, agents and many LLM/embedding providers. A `kurly.http` workload on the official image; its storage (embedded vector database, uploaded documents, settings) on a PersistentVolume under `/app/server/storage`.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local anythingllm = import 'github.com/metio/kurly/workloads/anythingllm/server.libsonnet';
kurly.list(anythingllm())
```

Storage at `/app/server/storage` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:3001`.

**Providers:** point it at your LLM and embedding providers with the documented environment variables. kurly authors no Secret; pass non-secret settings via `env` and provide API keys through a Secret (compose `kurly.envFromSecret` on).

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
metadata: { name: kurly, namespace: anythingllm }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-anythingllm, namespace: anythingllm }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/anythingllm, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: anythingllm }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-anythingllm, namespace: anythingllm }
spec: { sourceRef: { kind: OCIRepository, name: kurly-anythingllm } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: anythingllm, namespace: anythingllm }
spec:
  serviceAccountName: anythingllm-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/anythingllm/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-anythingllm, importPath: github.com/metio/kurly/workloads/anythingllm }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: anythingllm, namespace: anythingllm }
spec:
  serviceAccountName: anythingllm-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: anythingllm
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: anythingllm }
```

<!-- END generated: jaas-deploy -->
