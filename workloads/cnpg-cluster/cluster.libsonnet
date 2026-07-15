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
  database='app',
  owner='app',
  parameters={},
  resources=null,
  enablePodMonitor=true,
)
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
