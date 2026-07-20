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
function(
  name='maloja',
  image='docker.io/krateng/maloja:latest@sha256:4ecea26058d2ca5168a8d53820279942d28f0606664cea6425f42371d5d88f95',
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
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/mljdata', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
