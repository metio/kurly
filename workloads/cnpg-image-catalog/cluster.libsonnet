// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// cnpg-image-catalog/cluster — the PostgreSQL images every CloudNativePG
// cluster in the whole Kubernetes cluster may run, as a `ClusterImageCatalog`
// custom resource: one object serving every namespace.
//
//   local catalog = import 'github.com/metio/kurly/workloads/cnpg-image-catalog/cluster.libsonnet';
//   kurly.list(catalog(name='postgres', images={
//     '16': 'ghcr.io/cloudnative-pg/postgresql:16.6',
//     '17': 'ghcr.io/cloudnative-pg/postgresql:17.2',
//   }))
//
// CNPG gives ImageCatalog and ClusterImageCatalog an identical spec, so this is
// the namespaced catalog under the cluster-scoped kind — the choice between them
// is ownership and RBAC, not capability. A cluster-scoped object needs
// cluster-scoped RBAC to deploy and belongs to whoever owns the platform rather
// than to a database team; a cnpg-cluster points at it with catalogScope='cluster'.
//
// The blast radius is the whole point and worth restating at this scope:
// bumping an image here rolls EVERY cluster on that major in EVERY namespace,
// with no change to any Cluster CR.
//
// PREREQUISITE: the CloudNativePG operator must be installed in the cluster.
local namespaced = import './namespaced.libsonnet';

function(
  name='postgres',
  images={ '17': 'ghcr.io/cloudnative-pg/postgresql:17.2' },
  componentImages={},
)
  namespaced(name=name, images=images, componentImages=componentImages)
  { catalog+: { kind: 'ClusterImageCatalog' } }
