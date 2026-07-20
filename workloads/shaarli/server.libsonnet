// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// shaarli — a Shaarli server (a self-hosted, database-free bookmarking and link-sharing
// app: a personal, minimalist "delicious" you fully own). A plain composable kurly.http
// workload on the official image; because Shaarli is flat-file, its data (links, config,
// cache) lives on a PersistentVolume — no external database. Import it and render with
// kurly.list:
//
//   local shaarli = import 'github.com/metio/kurly/workloads/shaarli/server.libsonnet';
//   kurly.list(shaarli())
//
// Serves the web app on :80 — compose an exposure onto it.
//
// Single writer: the flat-file data lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='shaarli',
  image='docker.io/shaarli/shaarli:v0.16.3',
  storageSize='2Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env(env)
  // The bundled Apache/PHP-FPM master runs as root then serves as www-data; the root
  // filesystem stays writable for its runtime state.
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/var/www/shaarli/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
