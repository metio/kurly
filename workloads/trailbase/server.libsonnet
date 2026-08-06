// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// trailbase — a TrailBase server (a single-executable application backend: a
// SQLite database with type-safe REST and realtime APIs, authentication, a
// WebAssembly runtime and an admin UI, in one process). A plain composable
// kurly.http workload keeping its whole state — database, configuration,
// secrets, uploaded files — in one data directory on a PersistentVolume. Import
// it and render with kurly.list:
//
//   local trailbase = import 'github.com/metio/kurly/workloads/trailbase/server.libsonnet';
//   kurly.list(trailbase())
//
// Serves the APIs, the admin UI and anything in its own static directory on
// :4000 — compose an exposure onto it.
//
// The volume is mounted at /app/traildepot, the data directory the image's own
// command names, which is what upstream's compose file does too. That masks the
// WebAssembly components the image ships under it, so a component-backed
// deployment supplies them into the volume rather than expecting the image's
// copies to be visible.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='trailbase',
  image=defaultImage,
  // The database, the configuration, the auth keys and uploaded files all live
  // in the data directory, so this grows with the application built on it.
  storageSize='10Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(4000)
  + kurly.servicePort(4000)
  + (if env == {} then {} else kurly.env(env))
  // The image adds its own account and runs as it; the data directory it chowns
  // at build time is replaced by the volume here, so fsGroup is what makes that
  // volume writable.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/app/traildepot', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp')
  // A Service named after the workload injects TRAILBASE_PORT as a tcp:// URL;
  // the process reads its own environment for configuration, so keep the links
  // out of it.
  + kurly.disableServiceLinks()
  // The image's own healthcheck endpoint: public, and answering before the
  // first-run initialisation has produced a UI to serve.
  + kurly.startupProbe({ httpGet: { path: '/api/healthcheck', port: 'http' }, failureThreshold: 30, periodSeconds: 5 })
  + kurly.readinessProbe({ httpGet: { path: '/api/healthcheck', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/healthcheck', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
