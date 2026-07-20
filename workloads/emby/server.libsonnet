// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// emby — an Emby server (a self-hosted media server for streaming your movies, shows, music
// and photos to any device). A plain composable kurly.http workload on the LinuxServer.io
// image; its application config lives on a PersistentVolume. Import it and render with
// kurly.list:
//
//   local emby = import 'github.com/metio/kurly/workloads/emby/server.libsonnet';
//   kurly.list(emby())
//
// Serves the web app on :8096 — compose an exposure onto it.
//
// MEDIA: mount your media libraries (read-only is fine) and add them in the UI; compose the
// extra volumes on. The config volume holds only Emby's own state.
//
// LINUXSERVER IMAGE: the s6-overlay init runs as root and drops to the PUID/PGID user, so
// this runs as root with a writable root filesystem — kurly keeps the rest of the hardening.
//
// Single writer: the config lives on a ReadWriteOnce volume, so one replica, recreated.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='emby',
  image='lscr.io/linuxserver/emby:4.8.11',
  storageSize='10Gi',
  storageClass=null,
  puid=1000,
  pgid=1000,
  timezone='UTC',
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8096)
  + kurly.servicePort(8096)
  + kurly.env({ PUID: std.toString(puid), PGID: std.toString(pgid), TZ: timezone } + env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/config', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
