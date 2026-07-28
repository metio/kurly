// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// thelounge — a The Lounge server (a modern, self-hosted web IRC client: always-connected,
// multi-user, accessible from any browser). A plain composable kurly.http workload on the
// official image; its configuration and per-user data live on a PersistentVolume. Import it
// and render with kurly.list:
//
//   local thelounge = import 'github.com/metio/kurly/workloads/thelounge/server.libsonnet';
//   kurly.list(thelounge())
//
// Serves the web client on :9000 — compose an exposure onto it.
//
// Single writer: the data lives on a ReadWriteOnce volume, so one replica, recreated
// (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');
function(
  name='thelounge',
  image=defaultImage,
  storageSize='2Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(9000)
  + kurly.servicePort(9000)
  + kurly.env({ THELOUNGE_HOME: '/var/opt/thelounge' } + env)
  // The entrypoint adjusts its data directory before dropping to the app user.
  + kurly.rootUser()
  + kurly.keepCapabilities()
  + kurly.writableRootFilesystem()
  + kurly.store('/var/opt/thelounge', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
