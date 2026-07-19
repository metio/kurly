// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// shiori — a Shiori server (a simple, self-hosted bookmarks manager with web-page
// archiving). A plain composable kurly.http workload: it keeps its bookmarks and
// archived pages in SQLite on a PersistentVolume, so it needs no external database.
// Import it and render with kurly.list:
//
//   local shiori = import 'github.com/metio/kurly/workloads/shiori/server.libsonnet';
//   kurly.list(shiori())
//
// Serves the web UI and API on :8080 — compose an exposure onto it.
//
// Single writer: the SQLite database and archives live on a ReadWriteOnce volume,
// so one replica, recreated (never rolled) to keep two pods off the files. Point
// SHIORI_DATABASE_URL at external PostgreSQL/MySQL through env to scale past that.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='shiori',
  image='ghcr.io/go-shiori/shiori:v1.8.0',
  storageSize='2Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '25m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.command(['shiori', 'serve'])
  + kurly.env({ SHIORI_DIR: '/shiori', SHIORI_HTTP_PORT: '8080' } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/shiori', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ httpGet: { path: '/liveness', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/liveness', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
