// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// synapse — a Synapse server (the reference Matrix homeserver from the Matrix.org Foundation:
// run your own federated, end-to-end-encrypted chat). A plain composable kurly.http workload on
// the official image; its configuration, signing keys and (with the default SQLite backend)
// database live on a PersistentVolume, generated into it on first start. Import it, set your
// server name, and render with kurly.list:
//
//   local synapse = import 'github.com/metio/kurly/workloads/synapse/server.libsonnet';
//   kurly.list(synapse(serverName='matrix.example.com'))
//
// Serves the client-server and federation API on :8008 — compose an exposure onto it.
//
// FIRST RUN: the image generates a homeserver.yaml and signing keys into /data from
// SYNAPSE_SERVER_NAME on first start. The server name is baked into every id and cannot be
// changed later, so set it deliberately. For anything beyond a small instance, edit the
// generated homeserver.yaml on the volume to point at an external PostgreSQL (the default is
// SQLite) and to tune federation.
//
// Single writer: the config and database live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='synapse',
  image='docker.io/matrixdotorg/synapse:v1.119.0',
  storageSize='10Gi',
  storageClass=null,
  serverName=null,
  reportStats='no',
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  local baseEnv =
    { SYNAPSE_REPORT_STATS: reportStats }
    + (if serverName == null then {} else { SYNAPSE_SERVER_NAME: serverName });
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8008)
  + kurly.servicePort(8008)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
