<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# chatpad

[Chatpad AI](https://github.com/deiucanta/chatpad) — a self-hosted, clean web UI for OpenAI's chat models. A `kurly.http` workload on the official image. Conversations and the API key are stored client-side, so the server only serves static assets and holds no data.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local chatpad = import 'github.com/metio/kurly/workloads/chatpad/server.libsonnet';
kurly.list(chatpad())
```

Stateless — a plain, horizontally scalable Deployment. Serves on `:80`. The browser talks to OpenAI directly with the user's own key.

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
metadata: { name: kurly, namespace: chatpad }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-chatpad, namespace: chatpad }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/chatpad, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: chatpad }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-chatpad, namespace: chatpad }
spec: { sourceRef: { kind: OCIRepository, name: kurly-chatpad } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: chatpad, namespace: chatpad }
spec:
  serviceAccountName: chatpad-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/chatpad/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-chatpad, importPath: github.com/metio/kurly/workloads/chatpad }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: chatpad, namespace: chatpad }
spec:
  serviceAccountName: chatpad-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: chatpad
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: chatpad }
```

<!-- END generated: jaas-deploy -->
