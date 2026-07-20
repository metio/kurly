// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// wallos — a Wallos server (a self-hosted subscription tracker and budgeting tool: track
// recurring subscriptions, costs and renewal dates in one place). A plain composable
// kurly.http workload on the official image; its SQLite database lives on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local wallos = import 'github.com/metio/kurly/workloads/wallos/server.libsonnet';
//   kurly.list(wallos())
//
// Serves the web app on :80 — compose an exposure onto it.
//
// Single writer: the SQLite database lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='wallos',
  image='ghcr.io/ellite/wallos:4.4.0',
  storageSize='1Gi',
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
  // The bundled Apache/PHP master runs as root then serves as www-data; the root
  // filesystem stays writable for its runtime state.
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/var/www/html/db', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
