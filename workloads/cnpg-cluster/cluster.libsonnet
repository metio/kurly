// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// cnpg-cluster — a highly-available PostgreSQL cluster as a CloudNativePG
// `Cluster` custom resource. PostgreSQL on Kubernetes is always run through
// CNPG here, so this workload authors the CR directly (rather than composing a
// kurly base kind); the CNPG operator reconciles it into the StatefulSet, pods,
// Services, and failover machinery. Import it, adapt with the parameters below,
// and render with kurly.list:
//
//   local cnpg = import 'github.com/metio/kurly/workloads/cnpg-cluster/cluster.libsonnet';
//   kurly.list(cnpg(name='orders-db', instances=3, storageSize='20Gi'))
//
// PREREQUISITE: the CloudNativePG operator must be installed in the cluster.
local version = 'dev';

// The kurly label convention, applied to the CR so the same ownership marker and
// version stamp ride on it as on every other kurly manifest.
local labelsFor(name) = {
  'app.kubernetes.io/name': name,
  'app.kubernetes.io/managed-by': 'kurly',
  'app.kubernetes.io/version': version,
};

function(
  name='postgres',
  instances=3,
  storageSize='10Gi',
  storageClass=null,
  imageName=null,
  catalog=null,
  catalogScope='namespaced',
  major=null,
  database='app',
  owner='app',
  parameters={},
  resources=null,
  enablePodMonitor=true,
)
  // CNPG resolves the image from exactly one source. Naming both is a config
  // error the operator rejects, so fail the render instead of the apply.
  assert !(imageName != null && catalog != null) :
         'cnpg-cluster: imageName and catalog are mutually exclusive — the image comes from one source';
  // A catalog lists one image per major, so the reference has to say which
  // major this cluster pins; without it the operator cannot resolve an image.
  assert catalog == null || major != null :
         'cnpg-cluster: catalog requires major (the PostgreSQL major version this cluster pins)';
  assert catalogScope == 'namespaced' || catalogScope == 'cluster' :
         "cnpg-cluster: catalogScope must be 'namespaced' or 'cluster', got '" + catalogScope + "'";
  {
    cluster: {
      apiVersion: 'postgresql.cnpg.io/v1',
      kind: 'Cluster',
      metadata: {
        name: name,
        labels: labelsFor(name),
      },
      spec: std.prune({
        // Three instances give one primary and two hot-standby replicas, so a
        // single node loss keeps the cluster writable.
        instances: instances,
        // null lets the operator pick the PostgreSQL image matching its version.
        imageName: imageName,
        // Referencing a catalog moves the image choice out of this CR: the
        // catalog owns the patch for the pinned major, so a fleet-wide bump
        // never touches a Cluster. Note that the version this cluster runs then
        // no longer follows app.kubernetes.io/version — the label stamps the
        // kurly workload, not the PostgreSQL image the catalog resolves.
        imageCatalogRef: (
          if catalog == null then null else {
            apiGroup: 'postgresql.cnpg.io',
            kind: if catalogScope == 'cluster' then 'ClusterImageCatalog' else 'ImageCatalog',
            name: catalog,
            major: major,
          }
        ),
        storage: std.prune({
          size: storageSize,
          storageClass: storageClass,
        }),
        // A fresh cluster is bootstrapped with an application database and owner
        // role; the operator mints the credentials as a Secret.
        bootstrap: {
          initdb: {
            database: database,
            owner: owner,
          },
        },
        // Extra postgresql.conf parameters, merged over the operator defaults.
        postgresql: (if parameters == {} then null else { parameters: parameters }),
        resources: resources,
        // A PodMonitor for the Prometheus Operator, on by default.
        monitoring: (if enablePodMonitor then { enablePodMonitor: true } else null),
      }),
    },
  }
