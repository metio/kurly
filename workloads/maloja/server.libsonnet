// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// maloja — a Maloja server (a self-hosted music scrobble database and listening-statistics server,
// a self-hosted alternative to Last.fm). A plain composable kurly.http workload on the official
// image; its database (SQLite) and configuration live on a PersistentVolume under /mljdata. Import
// it and render with kurly.list:
//
//   local maloja = import 'github.com/metio/kurly/workloads/maloja/server.libsonnet';
//   kurly.list(maloja())
//
// Serves the web app and API on :42010 — compose an exposure onto it.
//
// Single writer: the SQLite database lives on a ReadWriteOnce volume, so one replica, recreated
// (never rolled) to keep two pods off the same database.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');
function(
  name='maloja',
  image=defaultImage,
  storageSize='2Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(42010)
  + kurly.servicePort(42010)
  + kurly.env(env)
  // The s6-overlay init prepares /run as root and drops to the app user.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  // Writes under /run; a scratch there keeps the rest of the root filesystem read-only.
  + kurly.scratch('/run')
  // Writes under /app; a scratch there keeps the rest of the root filesystem read-only.
  + kurly.scratch('/app')
  // Writes under /config; a scratch there keeps the rest of the root filesystem read-only.
  + kurly.scratch('/config')
  // Writes under /defaults; a scratch there keeps the rest of the root filesystem read-only.
  + kurly.scratch('/defaults')
  + kurly.store('/mljdata', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
