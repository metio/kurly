// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// matrix-conduit — a Conduit server (a lightweight, self-hosted Matrix homeserver written in
// Rust: run your own end-to-end-encrypted chat that federates with the Matrix network). A
// plain composable kurly.http workload on the official image; its embedded database lives on
// a PersistentVolume. Import it, set your server name, and render with kurly.list:
//
//   local conduit = import 'github.com/metio/kurly/workloads/matrix-conduit/server.libsonnet';
//   kurly.list(conduit(serverName='matrix.example.com'))
//
// Serves the Matrix client-server and federation API on :6167 — compose an exposure onto it.
//
// SERVER NAME IS PERMANENT: the server name is baked into every user and room id at first
// start and cannot be changed later, so set it deliberately. Federation also expects it to be
// reachable per the Matrix well-known / SRV rules.
//
// Single writer: the database lives on a ReadWriteOnce volume, so one replica, recreated
// (never rolled) to keep two pods off the store.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='matrix-conduit',
  image='docker.io/matrixconduit/matrix-conduit:v0.9.0',
  storageSize='10Gi',
  storageClass=null,
  serverName=null,
  allowRegistration=false,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv =
    {
      CONDUIT_DATABASE_PATH: '/var/lib/matrix-conduit',
      CONDUIT_DATABASE_BACKEND: 'rocksdb',
      CONDUIT_PORT: '6167',
      CONDUIT_ADDRESS: '0.0.0.0',
      CONDUIT_ALLOW_REGISTRATION: std.toString(allowRegistration),
    }
    + (if serverName == null then {} else { CONDUIT_SERVER_NAME: serverName });
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(6167)
  + kurly.servicePort(6167)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/var/lib/matrix-conduit', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
