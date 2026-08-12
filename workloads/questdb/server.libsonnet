// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// questdb — a time-series database that ingests fast and answers SQL, with a web
// console, a PostgreSQL-wire endpoint and a line-protocol ingest port. A plain
// composable kurly.http workload: everything it stores is one directory on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local questdb = import 'github.com/metio/kurly/workloads/questdb/server.libsonnet';
//   kurly.list(questdb())
//
// THREE PORTS, THREE AUDIENCES. :9000 is the web console and the REST API, :8812
// speaks the PostgreSQL wire protocol so existing clients and BI tools connect
// unchanged, and :9009 takes InfluxDB line protocol for ingest. All three are on
// the Service; expose only the ones that should be reachable, and remember that
// the console has no authentication of its own in the open-source build — an
// exposure without something in front of it publishes the database.
//
// RUNNING IT UNPRIVILEGED. The image's entrypoint chowns its data directory and
// re-execs through gosu ONLY when it starts as root; started as an ordinary user
// it runs the server directly. So the stage uses the image's own uid 10001 with
// fsGroup, and no privilege is relaxed.
//
// Single writer: QuestDB is one process owning one data directory on a
// ReadWriteOnce volume, so one replica, recreated (never rolled) — two would
// corrupt the tables rather than share them.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='questdb',
  image=defaultImage,
  storageSize='50Gi',
  storageClass=null,
  // QuestDB reserves memory outside the JVM heap for its column files, so the
  // limit here is what it may map, not what a heap setting caps.
  resources={ requests: { cpu: '500m', memory: '2Gi' }, limits: { memory: '4Gi' } },
  env={},
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(9000)
  + kurly.servicePort(9000)
  + kurly.extraPort('pgwire', 8812)
  + kurly.extraPort('ilp', 9009)
  + kurly.env({ QUESTDB_DATA_DIR: '/var/lib/questdb' } + env)
  // The uid the image's own questdb user carries — see the header for why that
  // keeps the entrypoint off its root path.
  + kurly.runAs(10001, gid=10001, fsGroup=10001)
  + kurly.store('/var/lib/questdb', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '256Mi')
  // Probed by connection: the console answers on :9000, and the endpoints that
  // look like health checks are queries, which a probe should not be running.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
