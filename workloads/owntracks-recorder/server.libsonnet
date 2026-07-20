// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// owntracks-recorder — an OwnTracks Recorder server (a self-hosted store and web UI for the
// location data your OwnTracks phone apps publish). A plain composable kurly.http workload on the
// official image; its location store lives on a PersistentVolume under /store. Import it and render
// with kurly.list:
//
//   local recorder = import 'github.com/metio/kurly/workloads/owntracks-recorder/server.libsonnet';
//   kurly.list(recorder())
//
// Serves the web UI and HTTP recorder endpoint on :8083 — compose an exposure onto it. The phone
// apps can publish to it over HTTP directly, or via an MQTT broker the Recorder subscribes to (set
// OTR_HOST/OTR_PORT in env to point at the broker).
//
// Single writer: the store is a ReadWriteOnce volume, so one replica, recreated (never rolled) to
// keep two pods off the same store directory.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='owntracks-recorder',
  image='docker.io/owntracks/recorder:latest@sha256:050c3ac9ed798d4110f12e53851e94f9fa0fcecb16cf4d7457967eac2e498da7',
  storageSize='5Gi',
  storageClass=null,
  env={ OTR_STORAGEDIR: '/store' },
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8083)
  + kurly.servicePort(8083)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/store', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
