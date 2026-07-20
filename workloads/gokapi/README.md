<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# gokapi

[Gokapi](https://github.com/Forceu/Gokapi) — a self-hosted, lightweight file-sharing server with expiring links and a download limit, similar to the discontinued Firefox Send. A `kurly.http` workload on the official image; database, configuration and (by default) stored files on a PersistentVolume under `/app/data`.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local gokapi = import 'github.com/metio/kurly/workloads/gokapi/server.libsonnet';
kurly.list(gokapi())
```

Data at `/app/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:53842`. Uploaded files can instead go to S3-compatible object storage when the `AWS_*` settings are provided.

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
metadata: { name: kurly, namespace: gokapi }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-gokapi, namespace: gokapi }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/gokapi, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: gokapi }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-gokapi, namespace: gokapi }
spec: { sourceRef: { kind: OCIRepository, name: kurly-gokapi } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: gokapi, namespace: gokapi }
spec:
  serviceAccountName: gokapi-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/gokapi/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-gokapi, importPath: github.com/metio/kurly/workloads/gokapi }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: gokapi, namespace: gokapi }
spec:
  serviceAccountName: gokapi-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: gokapi
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: gokapi }
```

<!-- END generated: jaas-deploy -->
