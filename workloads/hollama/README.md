<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# hollama

[Hollama](https://github.com/fmaclen/hollama) — a minimal, self-hosted web UI for Ollama and OpenAI-compatible LLMs. A `kurly.http` workload on the official image. Sessions and settings are stored client-side, so the server holds no data.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local hollama = import 'github.com/metio/kurly/workloads/hollama/server.libsonnet';
kurly.list(hollama())
```

Stateless — a plain, horizontally scalable Deployment. Serves on `:4173`. The browser talks to your Ollama / OpenAI endpoint directly; configure it in the UI.

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
metadata: { name: kurly, namespace: hollama }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-hollama, namespace: hollama }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/hollama, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: hollama }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-hollama, namespace: hollama }
spec: { sourceRef: { kind: OCIRepository, name: kurly-hollama } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: hollama, namespace: hollama }
spec:
  serviceAccountName: hollama-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/hollama/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-hollama, importPath: github.com/metio/kurly/workloads/hollama }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: hollama, namespace: hollama }
spec:
  serviceAccountName: hollama-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: hollama
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: hollama }
```

<!-- END generated: jaas-deploy -->
