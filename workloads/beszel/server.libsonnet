// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// beszel — a Beszel hub (a lightweight server-monitoring dashboard). This is the
// HUB: a plain composable kurly.http workload that keeps its data in SQLite on a
// PersistentVolume, so it needs no external database. Beszel agents run on the
// machines you monitor and report to this hub. Import it and render with kurly.list:
//
//   local beszel = import 'github.com/metio/kurly/workloads/beszel/server.libsonnet';
//   kurly.list(beszel())
//
// Serves the web UI and API on :8090 — compose an exposure onto it.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='beszel',
  image='ghcr.io/henrygd/beszel/beszel:0.18.7',
  storageSize='1Gi',
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
  + kurly.port(8090)
  + kurly.servicePort(8090)
  + (if env == {} then {} else kurly.env(env))
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/beszel_data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '32Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
