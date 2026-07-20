// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// cassandra-cluster — a highly-available Apache Cassandra cluster as a cass-operator
// `CassandraDatacenter` custom resource. Cassandra is Apache-2.0 (no SSPL/Elastic
// restriction), a clean default for a platform that monetizes hosting. This workload
// authors the CR directly (like cnpg-cluster); the operator reconciles it into the
// StatefulSet, pods, Services, and seed/rack topology.
//
//   local cassandra = import 'github.com/metio/kurly/workloads/cassandra-cluster/cluster.libsonnet';
//   kurly.list(cassandra(name='events', size=3, storageSize='100Gi'))
//
// PREREQUISITE: cass-operator (the DataStax Kubernetes Operator for Apache Cassandra,
// Apache-2.0) must be installed. The operator mints the superuser credentials as a
// Secret; point apps at the `<clusterName>-<name>-service` Service.
local version = std.rstripChars(importstr './version.txt', '\n');

local labelsFor(name) = {
  'app.kubernetes.io/name': name,
  'app.kubernetes.io/managed-by': 'kurly',
  'app.kubernetes.io/version': version,
};

function(
  // The datacenter name (metadata.name). clusterName defaults to it.
  name='cassandra',
  clusterName=null,
  // Nodes in this datacenter.
  size=3,
  serverVersion='4.1.7',
  storageSize='10Gi',
  storageClass=null,
  resources={ requests: { cpu: '1', memory: '2Gi' }, limits: { memory: '4Gi' } },
  // Extra cassandra.yaml / jvm config, passed VERBATIM (cass-operator's own schema).
  config={},
  labels={},
  annotations={},
)
  assert size >= 1 : 'cassandra-cluster: size must be at least 1';
  local cluster = if clusterName != null then clusterName else name;
  {
    // A kurly feature composed onto this workload writes a hidden config no base
    // reads here (it authors a custom resource), so it would silently do nothing —
    // fail the render instead. The raw + escape hatch still patches the CR.
    assert !std.objectHasAll(self, 'config') :
           'cassandra-cluster: kurly features do not apply to a custom resource — they write a config that no base reads here, so composing one would silently do nothing. '
           + "Use this workload's own parameters instead (labels/annotations, storageClass, size, resources, config), which are wired to the fields the operator honours.",
    datacenter: {
      apiVersion: 'cassandra.datastax.com/v1beta1',
      kind: 'CassandraDatacenter',
      metadata: std.prune({
        name: name,
        labels: labelsFor(name) + labels,
        annotations: (if annotations == {} then null else annotations),
      }),
      spec: std.prune({
        clusterName: cluster,
        serverType: 'cassandra',
        serverVersion: serverVersion,
        size: size,
        resources: resources,
        // The per-node data volume. cass-operator turns this into the StatefulSet's
        // volumeClaimTemplate, so each Cassandra node gets its own PersistentVolume.
        storageConfig: {
          cassandraDataVolumeClaimSpec: std.prune({
            storageClassName: storageClass,
            accessModes: ['ReadWriteOnce'],
            resources: { requests: { storage: storageSize } },
          }),
        },
        // Extra cassandra.yaml / JVM tuning, passed VERBATIM — cass-operator's own
        // schema (cassandra-yaml, jvm-server-options), which kurly does not model.
        config: (if config == {} then null else config),
        // The operator copies this onto the pods it generates — the Cassandra
        // counterpart to CNPG's inheritedMetadata.
        additionalLabels: (if labels == {} then null else labelsFor(name) + labels),
      }),
    },
  }
