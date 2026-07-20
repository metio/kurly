// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// tvheadend — a Tvheadend server (a self-hosted TV streaming server and DVR for Linux,
// supporting DVB, IPTV, SAT>IP and more, with a web UI). A plain composable kurly.http workload
// on the LinuxServer.io image; its config lives on a PersistentVolume. Import it and render with
// kurly.list:
//
//   local tvheadend = import 'github.com/metio/kurly/workloads/tvheadend/server.libsonnet';
//   kurly.list(tvheadend())
//
// Serves the web UI on :9981 — compose an exposure onto it. The HTSP streaming protocol on
// :9982 is published on the Service beside it (the 'htsp' port); tuners are hardware and are
// not modelled here.
//
// The image publishes only a rolling tag, so it is pinned by digest here; Renovate resolves and
// updates the digest. The s6-overlay init runs as root and drops to the PUID/PGID user.
//
// Single writer: the config lives on a ReadWriteOnce volume, so one replica, recreated.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='tvheadend',
  image='lscr.io/linuxserver/tvheadend:latest@sha256:ccd9f055f0eb5c78c43b40397e35ff30a884a40389222ef04f2e33efecbd3067',
  storageSize='2Gi',
  storageClass=null,
  puid=1000,
  pgid=1000,
  timezone='UTC',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(9981)
  + kurly.servicePort(9981)
  + kurly.extraPort('htsp', 9982)
  + kurly.env({ PUID: std.toString(puid), PGID: std.toString(pgid), TZ: timezone } + env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/config', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
