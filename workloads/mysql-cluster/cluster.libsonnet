// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mysql-cluster — a highly-available MySQL cluster as an Oracle MySQL Operator
// `InnoDBCluster` custom resource. MySQL on Kubernetes is run through the Oracle
// operator here (the Apache-2.0 upstream, not a proprietary DBaaS operator), so this
// workload authors the CR directly (rather than composing a kurly base kind); the
// operator reconciles it into a MySQL Group Replication cluster fronted by MySQL
// Router, with the StatefulSet, pods, Services, and failover machinery. Import it,
// adapt with the parameters below, and render with kurly.list:
//
//   local mysql = import 'github.com/metio/kurly/workloads/mysql-cluster/cluster.libsonnet';
//   kurly.list(mysql(name='orders-db', instances=3, storageSize='20Gi'))
//
// It is the MySQL counterpart to cnpg-cluster: an app that needs MySQL/MariaDB
// instead of PostgreSQL points its dbHost at this cluster's Service.
//
// PREREQUISITES:
//   - the MySQL Operator for Kubernetes (mysql-operator) must be installed.
//   - unlike CNPG, the operator does NOT mint the root credentials — you provide a
//     Secret (secretName) with keys `rootUser`, `rootHost`, and `rootPassword`.
//     kurly authors no Secret; fill it with kurly.externalSecret.
local version = std.rstripChars(importstr './version.txt', '\n');

// The kurly label convention, applied to the CR so the same ownership marker and
// version stamp ride on it as on every other kurly manifest.
local labelsFor(name) = {
  'app.kubernetes.io/name': name,
  'app.kubernetes.io/managed-by': 'kurly',
  'app.kubernetes.io/version': version,
};

function(
  name='mysql',
  // MySQL server instances (Group Replication members). Three gives one primary
  // and two secondaries; an odd count keeps a quorum.
  instances=3,
  // MySQL Router instances — the routing tier apps connect through. Two for HA.
  routerInstances=2,
  // The MySQL server version the operator pins (its container image tag).
  serverVersion='8.4.4',
  storageSize='10Gi',
  storageClass=null,
  // The consumer-provided Secret holding rootUser / rootHost / rootPassword. The
  // operator requires it; kurly mints none.
  secretName='mysql-root',
  resources=null,
  // Emit a self-signed CA/certs for in-cluster TLS. Turn off to supply your own
  // via the CR's tlsSecretName/tlsCASecretName through the raw + escape hatch.
  tlsUseSelfSigned=true,
  imagePullSecrets=[],
  labels={},
  annotations={},
)
  assert instances >= 1 : 'mysql-cluster: instances must be at least 1';
  {
    // A kurly feature composed onto this workload cannot work, and the failure is
    // invisible: features contribute to a hidden `config` that a BASE KIND reads
    // when it computes its manifests, and this workload has no base — it authors a
    // custom resource whose pods belong to an operator. So mysql-cluster() +
    // kurly.podLabels({…}) renders cleanly, exit 0, and the labels are simply gone.
    // The presence of `config` is exactly the fingerprint of a composed feature, so
    // the render fails and names the parameters that do work. The raw + escape hatch
    // still patches the resource itself, since that touches no config.
    assert !std.objectHasAll(self, 'config') :
           'mysql-cluster: kurly features do not apply to a custom resource — they write a config that no base reads here, so composing one would silently do nothing. '
           + "Use this workload's own parameters instead (labels/annotations, imagePullSecrets, resources, storageClass), which are wired to the fields the operator honours.",
    cluster: {
      apiVersion: 'mysql.oracle.com/v2',
      kind: 'InnoDBCluster',
      metadata: std.prune({
        name: name,
        labels: labelsFor(name) + labels,
        annotations: (if annotations == {} then null else annotations),
      }),
      spec: std.prune({
        // The Secret with the root credentials the operator bootstraps from. The
        // operator reads it; it does not create it — so the render fails later at
        // apply if it is missing, not here.
        secretName: secretName,
        tlsUseSelfSigned: tlsUseSelfSigned,
        instances: instances,
        version: serverVersion,
        router: { instances: routerInstances },
        // The per-instance data volume. The operator turns this into the
        // StatefulSet's volumeClaimTemplate, so each MySQL member gets its own
        // PersistentVolume — a ReadWriteOnce disk per pod, never shared.
        datadirVolumeClaimTemplate: std.prune({
          accessModes: ['ReadWriteOnce'],
          resources: { requests: { storage: storageSize } },
          storageClassName: storageClass,
        }),
        // Extra metadata the operator copies onto the pods it generates — the
        // MySQL counterpart to CNPG's inheritedMetadata, so network-policy
        // selectors and scrape hints reach the pods even though there is no pod
        // template here to attach kurly.podLabels() to.
        podLabels: (if labels == {} then null else labels),
        podAnnotations: (if annotations == {} then null else annotations),
        resources: resources,
        // The operator pulls the MySQL server and router images, so the pull
        // secrets belong to the CR — kurly.imagePullSecrets() is a pod-level
        // feature with no pod here to attach to.
        imagePullSecrets: (
          if imagePullSecrets == [] then null
          else [{ name: s } for s in imagePullSecrets]
        ),
      }),
    },
  }
