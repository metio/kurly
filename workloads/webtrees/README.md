<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# webtrees

[webtrees](https://www.webtrees.net) — a self-hosted, collaborative online genealogy application. A `kurly.http` workload on the community image, backed by an external MySQL/MariaDB, with data on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local webtrees = import 'github.com/metio/kurly/workloads/webtrees/server.libsonnet';
local mysql = import 'github.com/metio/kurly/workloads/mysql-cluster/cluster.libsonnet';
kurly.listOf(kurly.join([
  kurly.list(mysql(name='webtrees-db')).items,
  kurly.list(webtrees(baseUrl='https://tree.example.com')).items,
]))
```

The `DB_*` credentials come from a Secret via `envFrom` — kurly authors **no Secret**. Data at `/var/www/webtrees/data` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:80`.

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
metadata: { name: kurly, namespace: webtrees }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-webtrees, namespace: webtrees }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/webtrees, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: webtrees }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-webtrees, namespace: webtrees }
spec: { sourceRef: { kind: OCIRepository, name: kurly-webtrees } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: webtrees, namespace: webtrees }
spec:
  serviceAccountName: webtrees-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/webtrees/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-webtrees, importPath: github.com/metio/kurly/workloads/webtrees }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: webtrees, namespace: webtrees }
spec:
  serviceAccountName: webtrees-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: webtrees
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: webtrees }
```

<!-- END generated: jaas-deploy -->
