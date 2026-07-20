<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# open-webui

[Open WebUI](https://github.com/open-webui/open-webui) — a feature-rich, self-hosted web interface for chatting with local and remote LLMs (Ollama and any OpenAI-compatible API). A `kurly.http` workload on the official image; with the default SQLite backend its database and uploads on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local openWebui = import 'github.com/metio/kurly/workloads/open-webui/server.libsonnet';
kurly.list(openWebui(ollamaBaseUrl='http://ollama:11434'))
```

Set `WEBUI_SECRET_KEY` from a Secret via `envFrom`; kurly authors **no Secret**. Point it at an external PostgreSQL (`DATABASE_URL`) to scale past SQLite. Data at `/app/backend/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8080`.

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
metadata: { name: kurly, namespace: open-webui }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-open-webui, namespace: open-webui }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/open-webui, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: open-webui }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-open-webui, namespace: open-webui }
spec: { sourceRef: { kind: OCIRepository, name: kurly-open-webui } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: open-webui, namespace: open-webui }
spec:
  serviceAccountName: open-webui-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/open-webui/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-open-webui, importPath: github.com/metio/kurly/workloads/open-webui }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: open-webui, namespace: open-webui }
spec:
  serviceAccountName: open-webui-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: open-webui
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: open-webui }
```

<!-- END generated: jaas-deploy -->
