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

function(
  name='trilium',
  image='ghcr.io/triliumnext/trilium:v0.104.0',
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
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/home/node/trilium-data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ httpGet: { path: '/api/health-check', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
