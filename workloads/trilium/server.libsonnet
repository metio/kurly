// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// trilium — a TriliumNext Notes server (a hierarchical note-taking application for
// building personal knowledge bases). A plain composable kurly.http workload: it
// keeps its notes in a SQLite database on a PersistentVolume, so it needs no
// external database. Import it and render with kurly.list:
//
//   local trilium = import 'github.com/metio/kurly/workloads/trilium/server.libsonnet';
//   kurly.list(trilium())
//
// Serves the web app and sync API on :8080 — compose an exposure onto it.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='trilium',
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
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env({ TRILIUM_DATA_DIR: '/home/node/trilium-data' } + env)
  // The entrypoint hands its data directory to the node user.
  + kurly.rootUser()
  + kurly.keepCapabilities()
  + kurly.store('/home/node/trilium-data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '64Mi')
  // The Service is named after the app, so the Service-link environment defines
  // TRILIUM_PORT as a tcp:// URL — which the server reads as its listen port.
  + kurly.disableServiceLinks()
  + kurly.readinessProbe({ httpGet: { path: '/api/health-check', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
