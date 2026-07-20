<!--
SPDX-FileCopyrightText: The kurly Authors
SPDX-License-Identifier: 0BSD
-->

# cnpg-image-catalog

The PostgreSQL images a fleet of [CloudNativePG](https://cloudnative-pg.io/)
clusters may run, authored as an `ImageCatalog` or `ClusterImageCatalog` custom
resource — one stage each, since the scope is a different object, not a setting:

| Stage | Emits | Owned by |
|---|---|---|
| `namespaced` | `ImageCatalog` | the team that owns the databases; no cluster-scoped RBAC to deploy |
| `cluster` | `ClusterImageCatalog` | the platform; one object serves every namespace |

CNPG gives the two an identical spec, so the choice is ownership and RBAC, not
capability.

A catalog lists **one image per PostgreSQL major version**. A
[cnpg-cluster](../cnpg-cluster/) pins a major with `catalog=`/`major=`, and the
catalog owns the patch. That split is the point:

- a **patch bump** is one line here, and rolls every cluster on that major;
- a **major upgrade** stays a deliberate, per-cluster change.

**Prerequisite:** the CloudNativePG operator must be installed in the cluster.

## Compose

```jsonnet
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local catalog = import 'github.com/metio/kurly/workloads/cnpg-image-catalog/namespaced.libsonnet';

kurly.list(catalog(name='postgres', images={
  '16': 'ghcr.io/cloudnative-pg/postgresql:16.6',
  '17': 'ghcr.io/cloudnative-pg/postgresql:17.2',
}))
```

Swap the import for `cluster.libsonnet` to emit a `ClusterImageCatalog`; the
parameters are identical.

| Parameter | Default | Notes |
|---|---|---|
| `name` | `postgres` | catalog (and CR) name; a cluster's `catalog=` refers to it |
| `images` | `{ '17': … }` | `{ '<major>': '<image>' }`; keys must be major version numbers |
| `componentImages` | `{}` | sidecar/component image overrides, keyed by component name |
| `labels` / `annotations` | `{}` | applied to the catalog object; it generates no pods, so there is nothing to inherit |

## Pointing a cluster at it

```jsonnet
local cluster = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';

kurly.list(cluster(name='orders-db', catalog='postgres', major=17))
```

This renders `spec.imageCatalogRef` instead of `spec.imageName`. The two are
mutually exclusive — CNPG resolves the image from exactly one source, so
composing both fails the render rather than the apply. Pass
`catalogScope='cluster'` to point at a `ClusterImageCatalog`.

## Two things to know before adopting this

**A catalog bump changes no field on any Cluster.** Clusters roll because the
catalog they reference moved. This is the feature — a fleet-wide upgrade from one
line — and also the blast radius: bumping an image here rolls *every* cluster on
that major, at once. Stage it the way you would any other fleet rollout.

**The PostgreSQL version stops following `app.kubernetes.io/version`.** That label
stamps the kurly workload, not the image the catalog resolves. If you gate
[stageset migrations](https://stageset.projects.metio.wtf/gating/versioned-migrations/)
on the workload version (`spec.version.fromObject`), a catalog-driven PostgreSQL
upgrade will not cross any migration boundary — the label never moves. Gate on the
cluster's own version if a migration must fire on a PostgreSQL bump.

<!-- BEGIN generated: jaas-deploy -->

## Maturity

**e2e** — this workload is deployed to a live cluster by a smoke scenario and observed reaching readiness, on top of its test coverage.

## Deploy with JaaS

Make the kurly library and this workload importable as `JsonnetLibrary`s, render
each stages with a `JsonnetSnippet`, and roll them out with a `StageSet`. Both images
are single-layer, so a plain Flux `OCIRepository` pulls each one directly.

```yaml
# The kurly library (recipes) and this workload (source), both single-layer
# images from their release pipelines, pulled by plain OCIRepositories.
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly, namespace: cnpg-image-catalog }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly, ref: { tag: latest } }
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-cnpg-image-catalog, namespace: cnpg-image-catalog }
spec: { interval: 12h, url: oci://ghcr.io/metio/kurly/workloads/cnpg-image-catalog, ref: { tag: latest } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly, namespace: cnpg-image-catalog }
spec: { sourceRef: { kind: OCIRepository, name: kurly } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-cnpg-image-catalog, namespace: cnpg-image-catalog }
spec: { sourceRef: { kind: OCIRepository, name: kurly-cnpg-image-catalog } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: cnpg-image-catalog-cluster, namespace: cnpg-image-catalog }
spec:
  serviceAccountName: cnpg-image-catalog-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local cluster = import 'github.com/metio/kurly/workloads/cnpg-image-catalog/cluster.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(cluster())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-cnpg-image-catalog, importPath: github.com/metio/kurly/workloads/cnpg-image-catalog }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: cnpg-image-catalog-namespaced, namespace: cnpg-image-catalog }
spec:
  serviceAccountName: cnpg-image-catalog-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local namespaced = import 'github.com/metio/kurly/workloads/cnpg-image-catalog/namespaced.libsonnet';
      // Compose your exposure and any + features here, then render.
      kurly.list(namespaced())
  libraries:
    - { kind: JsonnetLibrary, name: kurly, importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-cnpg-image-catalog, importPath: github.com/metio/kurly/workloads/cnpg-image-catalog }
```

A `StageSet` deploys the stages in order, pinning artifact revisions at the start of
the run and gating each stage before the next.

```yaml
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: cnpg-image-catalog, namespace: cnpg-image-catalog }
spec:
  serviceAccountName: cnpg-image-catalog-deployer
  rollbackOnFailure: true
  stages:
    - name: cluster
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: cnpg-image-catalog-cluster
    - name: namespaced
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: cnpg-image-catalog-namespaced
```

<!-- END generated: jaas-deploy -->
