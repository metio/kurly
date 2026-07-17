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

## Deploy through JaaS and stageset

The operator, the catalog, and the clusters form a ladder where each rung is a
real dependency:

| Stage | Source | Why it must come first |
|---|---|---|
| `operator` | upstream's release manifest, via a Flux `GitRepository` | a catalog is a `postgresql.cnpg.io` CR, so the CRDs must be Established before it can apply |
| `images` | this workload | a cluster cannot resolve an image for a major the catalog does not list |
| `clusters` | [cnpg-cluster](../cnpg-cluster/) | — |

The operator stage points at CloudNativePG's own published manifest rather than
a kurly-authored copy: it is ~21k lines, nearly all of it the CRDs, and it is
CNPG's release artifact rather than anyone's intent to model. Gate that stage on
the CRDs, not only the Deployment — kstatus reports a CRD ready on its
`Established` condition, which is what the stage behind it actually needs.

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata: { name: cnpg-operator, namespace: postgres }
spec:
  interval: 12h
  url: https://github.com/cloudnative-pg/cloudnative-pg
  ref: { tag: v1.30.0 }
  ignore: |
    /*
    !/releases/cnpg-1.30.0.yaml
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata: { name: kurly-cnpg-image-catalog, namespace: postgres }
spec:
  interval: 12h
  url: oci://ghcr.io/metio/kurly/workloads/cnpg-image-catalog
  ref: { tag: latest }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetLibrary
metadata: { name: kurly-cnpg-image-catalog, namespace: postgres }
spec: { sourceRef: { kind: OCIRepository, name: kurly-cnpg-image-catalog } }
---
apiVersion: jaas.metio.wtf/v1
kind: JsonnetSnippet
metadata: { name: postgres-images, namespace: postgres }
spec:
  serviceAccountName: postgres-renderer
  files:
    main.jsonnet: |
      local kurly = import 'github.com/metio/kurly/main.libsonnet';
      local catalog = import 'github.com/metio/kurly/workloads/cnpg-image-catalog/namespaced.libsonnet';
      function(pg17='ghcr.io/cloudnative-pg/postgresql:17.2')
        kurly.list(catalog(name='postgres', images={ '17': pg17 }))
  libraries:
    - { kind: JsonnetLibrary, name: kurly,                     importPath: github.com/metio/kurly }
    - { kind: JsonnetLibrary, name: kurly-cnpg-image-catalog,  importPath: github.com/metio/kurly/workloads/cnpg-image-catalog }
  tlas:
    - name: pg17
      value: ghcr.io/cloudnative-pg/postgresql:17.2
---
apiVersion: stages.metio.wtf/v1
kind: StageSet
metadata: { name: postgres, namespace: postgres }
spec:
  serviceAccountName: postgres-deployer
  stages:
    - name: operator
      sourceRef: { kind: GitRepository, name: cnpg-operator }
      path: ./releases
      readyChecks:
        timeout: 5m
        checks:
          - apiVersion: apiextensions.k8s.io/v1
            kind: CustomResourceDefinition
            name: imagecatalogs.postgresql.cnpg.io
          - apiVersion: apiextensions.k8s.io/v1
            kind: CustomResourceDefinition
            name: clusters.postgresql.cnpg.io
          - apiVersion: apps/v1
            kind: Deployment
            name: cnpg-controller-manager
            namespace: cnpg-system
    - name: images
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: postgres-images
      readyChecks:
        checks:
          - apiVersion: postgresql.cnpg.io/v1
            kind: ImageCatalog
            name: postgres
    - name: cluster
      sourceRef:
        apiVersion: jaas.metio.wtf/v1
        kind: JsonnetSnippet
        name: postgres
      readyChecks:
        checks:
          - apiVersion: postgresql.cnpg.io/v1
            kind: Cluster
            name: orders-db
```
