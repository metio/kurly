// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// ferretdb — a FerretDB server (an open-source, MongoDB-compatible database). A
// plain composable kurly.http workload: FerretDB is a STATELESS proxy that speaks
// the MongoDB wire protocol and stores everything in a PostgreSQL backend (with the
// DocumentDB extension), so it needs no volume of its own and can run several
// replicas. Import it, point it at a backend, and render with kurly.list:
//
//   local ferretdb = import 'github.com/metio/kurly/workloads/ferretdb/server.libsonnet';
//   kurly.list(ferretdb())
//
// Serves the MongoDB wire protocol on :27017 — route it as TCP for MongoDB clients.
//
// WHY FerretDB: it is Apache-2.0 and MongoDB-wire-compatible — the permissive
// alternative to MongoDB Community (SSPL) for a platform that monetizes hosting. See
// the mongodb-cluster workload for the SSPL engine.
//
// BACKEND: FerretDB v2 needs a PostgreSQL with the DocumentDB extension. Run one with
// the cnpg-cluster workload pinned to the FerretDB image
// (imageName='ghcr.io/ferretdb/postgres-documentdb:...'), then point
// FERRETDB_POSTGRESQL_URL at it. kurly authors no Secret; the URL (with its password)
// comes from a provided Secret via envFrom.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='ferretdb',
  image='ghcr.io/ferretdb/ferretdb:2.7.0',
  // The Secret holding FERRETDB_POSTGRESQL_URL (with the backend password), via
  // envFrom. kurly mints none.
  secretName='ferretdb-secrets',
  replicas=1,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(27017)
  + kurly.servicePort(27017)
  + kurly.envFromSecret(secretName)
  + kurly.env({ FERRETDB_LISTEN_ADDR: ':27017' } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
