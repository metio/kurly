// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// gotify — a Gotify server (a simple server for sending and receiving push
// notifications). A plain composable kurly.http workload: it keeps its messages,
// apps, and clients in a SQLite database on a PersistentVolume, so it needs no
// external database. Import it and render with kurly.list:
//
//   local gotify = import 'github.com/metio/kurly/workloads/gotify/server.libsonnet';
//   kurly.list(gotify())
//
// Serves the web app and API on :80 — compose an exposure onto it.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='gotify',
  image='docker.io/gotify/server:3.0.0',
  storageSize='1Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '25m', memory: '32Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env({ GOTIFY_SERVER_PORT: '80', GOTIFY_DATABASE_DIALECT: 'sqlite3', GOTIFY_DATABASE_CONNECTION: '/app/data/gotify.db' } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/app/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '32Mi')
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
