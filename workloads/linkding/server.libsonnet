// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// linkding — a linkding server (a minimal, self-hosted bookmark manager). A plain
// composable kurly.http workload: it keeps its bookmarks in a SQLite database on a
// PersistentVolume, so it needs no external database. Import it and render with
// kurly.list:
//
//   local linkding = import 'github.com/metio/kurly/workloads/linkding/server.libsonnet';
//   kurly.list(linkding())
//
// Serves the web UI and API on :9090 — compose an exposure onto it.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file. Point LD_DB_ENGINE at
// external PostgreSQL through env to scale past that.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='linkding',
  image='docker.io/sissbruecker/linkding:1.45.0',
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
  + kurly.port(9090)
  + kurly.servicePort(9090)
  + (if env == {} then {} else kurly.env(env))
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/etc/linkding/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
