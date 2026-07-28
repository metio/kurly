<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# privatebin

[PrivateBin](https://privatebin.info) — a minimalist, open-source, zero-knowledge
pastebin: the server stores only encrypted blobs, with pastes encrypted and decrypted in
the browser. A plain composable `kurly.http` workload on the official nginx+php-fpm image;
with the default filesystem backend its encrypted pastes live on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local privatebin = import 'github.com/metio/kurly/workloads/privatebin/server.libsonnet';
kurly.list(privatebin())
```

Pastes at `/srv/data` on a ReadWriteOnce volume, so **one replica, recreated**. Point
PrivateBin at an external database (its `conf.php`) to scale out. Serves on `:8080`.

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
metadata: { name: kurly, namespace: privatebin }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-privatebin, namespace: privatebin }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/privatebin, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: privatebin }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-privatebin, namespace: privatebin }
spec: { sourceRef: { kind: OCIRepository, name: kurly-privatebin } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: privatebin, namespace: privatebin }
spec:
  serviceAccountName: privatebin-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/privatebin/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-privatebin, importPath: github.com/metio/kurly/workloads/privatebin }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: privatebin, namespace: privatebin }
spec:
  serviceAccountName: privatebin-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: privatebin
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: privatebin }
```

<!-- END generated: jaas-deploy -->
