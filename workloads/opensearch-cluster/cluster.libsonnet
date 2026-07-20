// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// opensearch-cluster — a highly-available OpenSearch cluster as an OpenSearch
// Operator `OpenSearchCluster` custom resource. OpenSearch is the Apache-2.0 fork of
// Elasticsearch; unlike Elasticsearch (SSPL / Elastic License), it carries no
// restriction on offering it as a service — the right default for a platform that
// monetizes hosting. This workload authors the CR directly (like cnpg-cluster); the
// operator reconciles it into the StatefulSets, Services, security config, and
// optional Dashboards. Import it, adapt with the parameters below, and render with
// kurly.list:
//
//   local opensearch = import 'github.com/metio/kurly/workloads/opensearch-cluster/cluster.libsonnet';
//   kurly.list(opensearch(name='logs', replicas=3, storageSize='50Gi'))
//
// PREREQUISITE: the OpenSearch Operator (opensearch-operator) must be installed.
local version = std.rstripChars(importstr './version.txt', '\n');

local labelsFor(name) = {
  'app.kubernetes.io/name': name,
  'app.kubernetes.io/managed-by': 'kurly',
  'app.kubernetes.io/version': version,
};

function(
  name='opensearch',
  // Nodes in the default pool. Each is cluster_manager + data + ingest; split into
  // dedicated pools through the raw + escape hatch for large clusters.
  replicas=3,
  // The OpenSearch version the operator pins (server and Dashboards image tag).
  opensearchVersion='2.19.1',
  storageSize='10Gi',
  storageClass=null,
  resources={ requests: { cpu: '500m', memory: '2Gi' }, limits: { memory: '4Gi' } },
  // Run OpenSearch Dashboards (the Kibana equivalent) alongside the cluster.
  dashboards=true,
  dashboardsReplicas=1,
  labels={},
  annotations={},
)
  assert replicas >= 1 : 'opensearch-cluster: replicas must be at least 1';
  {
    // A kurly feature composed onto this workload writes a hidden config no base
    // reads here (it authors a custom resource), so it would silently do nothing —
    // fail the render instead. The raw + escape hatch still patches the CR.
    assert !std.objectHasAll(self, 'config') :
           'opensearch-cluster: kurly features do not apply to a custom resource — they write a config that no base reads here, so composing one would silently do nothing. '
           + "Use this workload's own parameters instead (labels/annotations, resources, storageClass, replicas), which are wired to the fields the operator honours.",
    cluster: {
      apiVersion: 'opensearch.opster.io/v1',
      kind: 'OpenSearchCluster',
      metadata: std.prune({
        name: name,
        labels: labelsFor(name) + labels,
        annotations: (if annotations == {} then null else annotations),
      }),
      spec: {
        general: {
          serviceName: name,
          version: opensearchVersion,
          httpPort: 9200,
          // The operator copies these onto the objects it generates, the OpenSearch
          // counterpart to CNPG's inheritedMetadata — so kurly's ownership labels
          // and any scrape hints reach the pods even without a pod template here.
          additionalConfig: {},
        },
        dashboards: {
          enable: dashboards,
          version: opensearchVersion,
          replicas: (if dashboards then dashboardsReplicas else 0),
        },
        nodePools: [
          std.prune({
            component: 'nodes',
            replicas: replicas,
            diskSize: storageSize,
            roles: ['cluster_manager', 'data', 'ingest'],
            persistence: { pvc: std.prune({
              storageClass: storageClass,
              accessModes: ['ReadWriteOnce'],
            }) },
            resources: resources,
            labels: labelsFor(name) + labels,
            annotations: (if annotations == {} then null else annotations),
          }),
        ],
      },
    },
  }
