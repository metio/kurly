<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# nocobase

[NocoBase](https://www.nocobase.com) — a self-hosted, open-source no-code/low-code platform for building internal tools, databases and workflows. A `kurly.http` workload on the official image, backed by an external PostgreSQL, with storage on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local nocobase = import 'github.com/metio/kurly/workloads/nocobase/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
kurly.listOf(kurly.join([
  kurly.list(cnpg(name='nocobase-db', database='nocobase')).items,
  kurly.list(nocobase()).items,
]))
```

The `DB_*` connection and `APP_KEY` come from a Secret via `envFrom` — kurly authors **no Secret**. Storage at `/app/nocobase/storage` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:80`.

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
metadata: { name: kurly, namespace: nocobase }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-nocobase, namespace: nocobase }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/nocobase, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: nocobase }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-nocobase, namespace: nocobase }
spec: { sourceRef: { kind: OCIRepository, name: kurly-nocobase } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: nocobase, namespace: nocobase }
spec:
  serviceAccountName: nocobase-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/nocobase/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-nocobase, importPath: github.com/metio/kurly/workloads/nocobase }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: nocobase, namespace: nocobase }
spec:
  serviceAccountName: nocobase-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: nocobase
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: nocobase }
```

<!-- END generated: jaas-deploy -->
