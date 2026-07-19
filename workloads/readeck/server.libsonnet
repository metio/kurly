// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// readeck — a Readeck server (a self-hosted read-it-later and web-bookmarking tool
// that saves clean, readable copies of pages). A plain composable kurly.http
// workload: it keeps its bookmarks and saved articles in SQLite on a
// PersistentVolume, so it needs no external database. Import it and render with
// kurly.list:
//
//   local readeck = import 'github.com/metio/kurly/workloads/readeck/server.libsonnet';
//   kurly.list(readeck())
//
// Serves the web UI and API on :8000 — compose an exposure onto it.
//
// Single writer: the SQLite database and saved pages live on a ReadWriteOnce
// volume, so one replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='readeck',
  image='codeberg.org/readeck/readeck:0.22.3',
  storageSize='2Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '25m', memory: '64Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8000)
  + kurly.servicePort(8000)
  + kurly.env({ READECK_SERVER_HOST: '0.0.0.0', READECK_SERVER_PORT: '8000', READECK_DATA_DIRECTORY: '/readeck' } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/readeck', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ httpGet: { path: '/api/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/health', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
