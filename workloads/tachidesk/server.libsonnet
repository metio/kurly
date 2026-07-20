// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// tachidesk — a Suwayomi-Server (formerly Tachidesk): a self-hosted, free and open-source
// manga reader and library server, a server-side companion to the Tachiyomi/Mihon app
// ecosystem. A plain composable kurly.http workload on the official image; its library,
// downloads and settings live on a PersistentVolume. Import it and render with kurly.list:
//
//   local tachidesk = import 'github.com/metio/kurly/workloads/tachidesk/server.libsonnet';
//   kurly.list(tachidesk())
//
// Serves the web reader and API on :4567 — compose an exposure onto it.
//
// Single writer: the library lives on a ReadWriteOnce volume, so one replica, recreated
// (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='tachidesk',
  image='ghcr.io/suwayomi/tachidesk:v2.1.1867',
  storageSize='20Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(4567)
  + kurly.servicePort(4567)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/home/suwayomi/.local/share/Tachidesk', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
