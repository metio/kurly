// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// grist — a Grist server (a self-hosted, open-source relational spreadsheet: the flexibility of a
// spreadsheet with the structure of a database, plus Python formulas and access rules). A plain
// composable kurly.http workload on the official image; its documents (SQLite) live on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local grist = import 'github.com/metio/kurly/workloads/grist/server.libsonnet';
//   kurly.list(grist())
//
// Serves the web app on :8484 — compose an exposure onto it.
//
// Single writer: the documents live on a ReadWriteOnce volume, so one replica, recreated (never
// rolled) to keep two pods off the SQLite files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='grist',
  image='docker.io/gristlabs/grist:1.2.0',
  storageSize='10Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8484)
  + kurly.servicePort(8484)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/persist', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/status', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
