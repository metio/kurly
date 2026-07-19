// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// actualbudget — an Actual Budget server (a local-first personal finance and
// budgeting app). A plain composable kurly.http workload: it keeps its budgets and
// sync state in a SQLite database on a PersistentVolume, so it needs no external
// database. Import it and render with kurly.list:
//
//   local actual = import 'github.com/metio/kurly/workloads/actualbudget/server.libsonnet';
//   kurly.list(actual())
//
// Serves the web app and sync API on :5006 — compose an exposure onto it.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='actualbudget',
  image='docker.io/actualbudget/actual-server:26.7.0',
  storageSize='2Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(5006)
  + kurly.servicePort(5006)
  + kurly.env({ ACTUAL_DATA_DIR: '/data' } + env)
  // The image runs as node (uid 1000); pin it and its fsGroup so the data volume
  // is writable and the restricted posture admits the pod.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
