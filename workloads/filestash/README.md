<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# filestash

[Filestash](https://www.filestash.app) — a self-hosted web file manager with a modern UI in front of many storage backends (SFTP, FTP, S3, WebDAV, Git). A `kurly.http` workload on the official image (pinned by digest — Renovate maintains it); config on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local filestash = import 'github.com/metio/kurly/workloads/filestash/server.libsonnet';
kurly.list(filestash())
```

Add storage backends in the admin console; files live on those backends. Config at `/app/data/state` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8334`.

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
metadata: { name: kurly, namespace: filestash }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-filestash, namespace: filestash }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/filestash, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: filestash }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-filestash, namespace: filestash }
spec: { sourceRef: { kind: OCIRepository, name: kurly-filestash } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: filestash, namespace: filestash }
spec:
  serviceAccountName: filestash-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/filestash/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-filestash, importPath: github.com/metio/kurly/workloads/filestash }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: filestash, namespace: filestash }
spec:
  serviceAccountName: filestash-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: filestash
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: filestash }
```

<!-- END generated: jaas-deploy -->
