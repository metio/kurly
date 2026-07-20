// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// pocketbase — a PocketBase server (a self-hosted, open-source backend in one file: an embedded
// SQLite database, auth, file storage and a REST/realtime API, with an admin dashboard). A plain
// composable kurly.http workload; its database, uploaded files and migrations live on a
// PersistentVolume under /pb_data. Import it and render with kurly.list:
//
//   local pocketbase = import 'github.com/metio/kurly/workloads/pocketbase/server.libsonnet';
//   kurly.list(pocketbase())
//
// Serves the API and admin UI on :8080 — compose an exposure onto it. On first run, create the
// superuser via the admin UI or the CLI.
//
// Single writer: the SQLite database lives on a ReadWriteOnce volume, so one replica, recreated
// (never rolled) to keep two pods off the same database.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='pocketbase',
  image='ghcr.io/muchobien/pocketbase:latest@sha256:cd66d436afed100204a62b03810eb75c5b70edbaf377b68230f1f799bafc4952',
  storageSize='5Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/pb_data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/api/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/health', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
