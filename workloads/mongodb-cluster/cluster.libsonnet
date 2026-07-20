// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mongodb-cluster — a highly-available MongoDB replica set as a MongoDB Community
// Operator `MongoDBCommunity` custom resource. This workload authors the CR directly
// (like cnpg-cluster); the operator reconciles it into the StatefulSet, pods,
// Services, and replica-set configuration.
//
//   local mongodb = import 'github.com/metio/kurly/workloads/mongodb-cluster/cluster.libsonnet';
//   kurly.list(mongodb(name='sessions', members=3, storageSize='20Gi'))
//
// ⚠ LICENSING: MongoDB Community Edition is licensed under the **SSPL**, which
// restricts offering MongoDB as a service — the same clause that makes Elasticsearch
// unsuitable for a monetized hosting platform. The OPERATOR is Apache-2.0, but the
// SERVER is not. If SSPL is a problem for your business model, prefer FerretDB
// (Apache-2.0, MongoDB-wire-compatible, runs on PostgreSQL) instead.
//
// PREREQUISITES:
//   - the MongoDB Community Operator (mongodb-kubernetes-operator) must be installed.
//   - you provide the admin user's password Secret (secretName) with a `password`
//     key. kurly authors no Secret; fill it with kurly.externalSecret.
local version = std.rstripChars(importstr './version.txt', '\n');

local labelsFor(name) = {
  'app.kubernetes.io/name': name,
  'app.kubernetes.io/managed-by': 'kurly',
  'app.kubernetes.io/version': version,
};

function(
  name='mongodb',
  // Replica-set members. Three gives one primary and two secondaries; an odd count
  // keeps a quorum.
  members=3,
  mongodbVersion='8.0.4',
  storageSize='10Gi',
  storageClass=null,
  logsSize='2Gi',
  // The admin user created on bootstrap and the Secret its password is read from.
  adminUser='admin',
  secretName='mongodb-admin',
  labels={},
  annotations={},
)
  assert members >= 1 : 'mongodb-cluster: members must be at least 1';
  {
    // A kurly feature composed onto this workload writes a hidden config no base
    // reads here (it authors a custom resource), so it would silently do nothing —
    // fail the render instead. The raw + escape hatch still patches the CR.
    assert !std.objectHasAll(self, 'config') :
           'mongodb-cluster: kurly features do not apply to a custom resource — they write a config that no base reads here, so composing one would silently do nothing. '
           + "Use this workload's own parameters instead (labels/annotations, storageClass, members), which are wired to the fields the operator honours.",
    cluster: {
      apiVersion: 'mongodbcommunity.mongodb.com/v1',
      kind: 'MongoDBCommunity',
      metadata: std.prune({
        name: name,
        labels: labelsFor(name) + labels,
        annotations: (if annotations == {} then null else annotations),
      }),
      spec: {
        members: members,
        type: 'ReplicaSet',
        version: mongodbVersion,
        security: {
          authentication: { modes: ['SCRAM'] },
        },
        // The admin user, its password read from the consumer-provided Secret. The
        // operator computes the SCRAM credentials into a Secret of its own.
        users: [{
          name: adminUser,
          db: 'admin',
          passwordSecretRef: { name: secretName },
          roles: [
            { name: 'clusterAdmin', db: 'admin' },
            { name: 'userAdminAnyDatabase', db: 'admin' },
            { name: 'readWriteAnyDatabase', db: 'admin' },
          ],
          scramCredentialsSecretName: name + '-scram',
        }],
        // The operator owns the pods, so storage and pod metadata are set through
        // its StatefulSet override rather than a kurly base kind. data-volume holds
        // the database, logs-volume the mongod logs.
        statefulSet: { spec: {
          volumeClaimTemplates: [
            { metadata: { name: 'data-volume' }, spec: std.prune({
              accessModes: ['ReadWriteOnce'],
              resources: { requests: { storage: storageSize } },
              storageClassName: storageClass,
            }) },
            { metadata: { name: 'logs-volume' }, spec: std.prune({
              accessModes: ['ReadWriteOnce'],
              resources: { requests: { storage: logsSize } },
              storageClassName: storageClass,
            }) },
          ],
          template: { metadata: std.prune({
            labels: labelsFor(name) + labels,
            annotations: (if annotations == {} then null else annotations),
          }) },
        } },
      },
    },
  }
