<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# misskey

[Misskey](https://misskey-hub.net) — a self-hosted, feature-rich ActivityPub/Fediverse social platform. A `kurly.http` workload on the official image, backed by an external PostgreSQL and Redis, with uploaded files on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local misskey = import 'github.com/metio/kurly/workloads/misskey/server.libsonnet';
kurly.list(misskey())
```

Misskey reads its whole config (including DB/Redis credentials) from `/misskey/.config/default.yml`. Because that holds secrets, kurly mounts it from an **existing Secret** you provide (`misskey-config`, with a `default.yml` key) — kurly never mints key material. Files at `/misskey/files` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:3000`.

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
metadata: { name: kurly, namespace: misskey }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-misskey, namespace: misskey }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/misskey, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: misskey }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-misskey, namespace: misskey }
spec: { sourceRef: { kind: OCIRepository, name: kurly-misskey } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: misskey, namespace: misskey }
spec:
  serviceAccountName: misskey-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/misskey/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-misskey, importPath: github.com/metio/kurly/workloads/misskey }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: misskey, namespace: misskey }
spec:
  serviceAccountName: misskey-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: misskey
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: misskey }
```

<!-- END generated: jaas-deploy -->
