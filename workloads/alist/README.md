<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# alist

[AList](https://alist.nn.ci) — a self-hosted file list / WebDAV program fronting many storage backends (local disk, S3, WebDAV, cloud drives) behind one web UI. A `kurly.http` workload on the official image; SQLite database and configuration on a PersistentVolume under `/opt/alist/data`.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local alist = import 'github.com/metio/kurly/workloads/alist/server.libsonnet';
kurly.list(alist())
```

Data at `/opt/alist/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves the UI and WebDAV on `:5244`. On first start it logs a randomly generated admin password — read it from the pod logs.

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
metadata: { name: kurly, namespace: alist }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-alist, namespace: alist }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/alist, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: alist }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-alist, namespace: alist }
spec: { sourceRef: { kind: OCIRepository, name: kurly-alist } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: alist, namespace: alist }
spec:
  serviceAccountName: alist-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/alist/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-alist, importPath: github.com/metio/kurly/workloads/alist }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: alist, namespace: alist }
spec:
  serviceAccountName: alist-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: alist
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: alist }
```

<!-- END generated: jaas-deploy -->
