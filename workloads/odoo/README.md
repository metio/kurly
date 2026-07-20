<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# odoo

[Odoo](https://www.odoo.com) — a self-hosted, all-in-one business/ERP suite: CRM, sales, inventory, accounting, website and more. A `kurly.http` workload on the official image, backed by an external PostgreSQL, with its filestore on a PersistentVolume.

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local odoo = import 'github.com/metio/kurly/workloads/odoo/server.libsonnet';
local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
kurly.listOf(kurly.join([
  kurly.list(cnpg(name='odoo-db', database='odoo')).items,
  kurly.list(odoo()).items,
]))
```

The PostgreSQL connection (`HOST`/`USER`/`PASSWORD`) comes from a Secret via `envFrom` — kurly authors **no Secret**. Filestore at `/var/lib/odoo` on a ReadWriteOnce volume, so **one replica, recreated**. Serves on `:8069`.

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
metadata: { name: kurly, namespace: odoo }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-odoo, namespace: odoo }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/odoo, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: odoo }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-odoo, namespace: odoo }
spec: { sourceRef: { kind: OCIRepository, name: kurly-odoo } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: odoo, namespace: odoo }
spec:
  serviceAccountName: odoo-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local server = import 'github.com/metio/kurly/workloads/odoo/server.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(server())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-odoo, importPath: github.com/metio/kurly/workloads/odoo }
```

A `StageSet` deploys the stage in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: odoo, namespace: odoo }
spec:
  serviceAccountName: odoo-deployer
  rollbackOnFailure: true
  stages:
    - name: server
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: odoo
      readyChecks:
        checks:
          - { apiVersion: apps/v1, kind: Deployment, name: odoo }
```

<!-- END generated: jaas-deploy -->
