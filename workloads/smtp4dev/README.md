<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# smtp4dev

[smtp4dev](https://github.com/rnwood/smtp4dev) — a self-hosted fake SMTP server for development: it receives the mail your apps send and shows it in a web UI, without delivering anything onward. A `kurly.http` workload on the official image, listening on **two ports** (the web UI and the SMTP sink) via `kurly.extraPort`; message database on a PersistentVolume under `/smtp4dev`.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local smtp4dev = import 'github.com/metio/kurly/workloads/smtp4dev/server.libsonnet';
kurly.list(smtp4dev())
```

Database at `/smtp4dev` on a ReadWriteOnce volume, so **one replica, recreated**. Serves the web UI on `:80` and accepts SMTP on `:25` — point your apps' SMTP client at the Service on port 25, and compose an exposure onto the web port.

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
metadata: { name: kurly, namespace: smtp4dev }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-smtp4dev, namespace: smtp4dev }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/smtp4dev, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: smtp4dev }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-smtp4dev, namespace: smtp4dev }
spec: { sourceRef: { kind: OCIRepository, name: kurly-smtp4dev } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: smtp4dev, namespace: smtp4dev }
spec:
  serviceAccountName: smtp4dev-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/smtp4dev/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-smtp4dev, importPath: github.com/metio/kurly/workloads/smtp4dev }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: smtp4dev, namespace: smtp4dev }
spec:
  serviceAccountName: smtp4dev-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: smtp4dev
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: smtp4dev }
```

<!-- END generated: jaas-deploy -->
