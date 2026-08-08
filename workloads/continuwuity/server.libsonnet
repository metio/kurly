// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// continuwuity — a Continuwuity server (the community-driven continuation of conduwuit and
// Conduit: a Matrix homeserver written in Rust that federates with the Matrix network). A
// plain composable kurly.http workload on the official image; its embedded RocksDB lives on
// a PersistentVolume. Import it, set your server name, and render with kurly.list:
//
//   local continuwuity = import 'github.com/metio/kurly/workloads/continuwuity/server.libsonnet';
//   kurly.list(continuwuity(serverName='matrix.example.com'))
//
// Serves the Matrix client-server and federation API on :8008 — compose an exposure onto it.
//
// SERVER NAME IS PERMANENT: it is baked into every user and room id at first start and
// cannot be changed later, so set it deliberately, and make it reachable per the Matrix
// well-known / SRV rules.
//
// Settings are read from the environment under the CONDUWUIT_ prefix — the fork kept its
// ancestor's names rather than renaming a contract every deployment already carries — and
// CONDUWUIT_CONFIG is set to the empty string because the binary insists on a config path
// even when every setting comes from the environment.
//
// SERVICE LINKS ARE OFF: a Service named after this workload makes Kubernetes inject
// CONTINUWUITY_PORT as a tcp:// URL, and the binary reads that prefix too, so it would try
// to parse a URL as its listen port.
//
// Single writer: one RocksDB on a ReadWriteOnce volume, so one replica, recreated (never
// rolled) — two servers opening the same database is not something either of them will sort
// out afterwards.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');
function(
  name='continuwuity',
  image=defaultImage,
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
      CONDUWUIT_CONFIG: '',
      CONDUWUIT_DATABASE_PATH: '/var/lib/conduwuit',
      CONDUWUIT_PORT: '8008',
      CONDUWUIT_ADDRESS: '0.0.0.0',
      CONDUWUIT_ALLOW_REGISTRATION: std.toString(allowRegistration),
    }
    + (if serverName == null then {} else { CONDUWUIT_SERVER_NAME: serverName });
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8008)
  + kurly.servicePort(8008)
  + kurly.env(baseEnv + env)
  + kurly.disableServiceLinks()
  // The image declares no user and the binary writes nothing but its database, which fsGroup
  // hands over; the listening port is above 1024.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/var/lib/conduwuit', storageSize, storageClass=storageClass)
  // Probe by connection: the Matrix endpoints answer only after the database is open, and
  // an unauthenticated GET on the API is not a health check.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
