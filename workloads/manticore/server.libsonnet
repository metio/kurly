// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// manticore — a Manticore Search server (a full-text search and analytics
// database: SQL over a MySQL-compatible port, JSON over HTTP, vector and full-text
// search in one engine). A plain composable kurly.http workload: indexes live on a
// PersistentVolume and it needs nothing external. Import it and render with
// kurly.list:
//
//   local manticore = import 'github.com/metio/kurly/workloads/manticore/server.libsonnet';
//   kurly.list(manticore())
//
// Serves the JSON API on :9308, which is the port an exposure attaches to. Two
// more are on the Service and are NOT HTTP, so no Ingress or HTTPRoute can carry
// them:
//
//   9306/TCP   the MySQL protocol — what `mysql -P9306` and most clients speak
//   9312/TCP   the binary protocol, for replication between nodes
//
// Search engines answer whoever asks them, and this one has no authentication of
// its own. Keep it inside the cluster, or put something in front that authenticates
// — an exposure on :9308 publishes an unauthenticated database.
//
// Single writer: one index directory on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two searchd processes off the same files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='manticore',
  image=defaultImage,
  storageSize='10Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(9308)
  + kurly.servicePort(9308)
  + kurly.extraPort('mysql', 9306)
  + kurly.extraPort('binary', 9312)
  + (if env == {} then {} else kurly.env(env))
  // The entrypoint chowns its directories and drops to the `manticore` account
  // with gosu, but only when it starts as root — it tests `id -u` first and
  // otherwise runs searchd directly. Naming that account (999, the one the image
  // built) takes the second path, so the hardened posture holds and fsGroup is
  // what makes the volume writable instead.
  + kurly.runAs(999, gid=999, fsGroup=999)
  + kurly.store('/var/lib/manticore', storageSize, storageClass=storageClass)
  // searchd writes outside the data directory in three places, and the MySQL one
  // is the surprise: the shipped config listens on a UNIX socket at
  // /var/run/mysqld/mysqld.sock — a mysqld path, in a search engine — and searchd
  // unlinks it before binding. On a read-only filesystem that is FATAL and the
  // only clue is `unlink() on UNIX socket file failed`, which names neither the
  // path nor the setting that chose it.
  + kurly.scratch('/var/run/mysqld')
  + kurly.scratch('/var/run/manticore')
  + kurly.scratch('/var/log/manticore')
  // The JSON port answers /sql without authentication, so readiness is a
  // connection check rather than a query that would need one.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
