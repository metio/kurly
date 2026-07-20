// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// pingvin-share — a Pingvin Share server (a self-hosted, open-source file-sharing platform, an
// alternative to WeTransfer). A plain composable kurly.http workload on the official all-in-one
// image (frontend + backend behind its own reverse proxy); its SQLite database and uploaded shares
// live on a PersistentVolume under /opt/app/backend/data. Import it and render with kurly.list:
//
//   local pingvin = import 'github.com/metio/kurly/workloads/pingvin-share/server.libsonnet';
//   kurly.list(pingvin())
//
// Serves the web app on :3000 — compose an exposure onto it.
//
// Single writer: the SQLite database and share files live on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the same data directory.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='pingvin-share',
  image='ghcr.io/stonith404/pingvin-share:latest@sha256:6bf2bcd3043ee68cb61264f0857511ccf7f212fdb984382b7f2d491635184ad6',
  storageSize='10Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/opt/app/backend/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
