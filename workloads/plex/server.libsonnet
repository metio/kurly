// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// plex — a Plex Media Server (a self-hosted media server for organising and streaming your
// movies, shows, music and photos to any device). A plain composable kurly.http workload on
// the LinuxServer.io image; its application config lives on a PersistentVolume. Import it and
// render with kurly.list:
//
//   local plex = import 'github.com/metio/kurly/workloads/plex/server.libsonnet';
//   kurly.list(plex())
//
// Serves the web app and API on :32400 — compose an exposure onto it.
//
// CLAIM & MEDIA: to bind the server to your Plex account on first run, set a PLEX_CLAIM token
// (from plex.tv/claim) via env; mount your media libraries and add them in the UI. The config
// volume holds only Plex's own state.
//
// LINUXSERVER IMAGE: the s6-overlay init runs as root and drops to the PUID/PGID user, so this
// runs as root with a writable root filesystem — kurly keeps the rest of the hardening.
//
// Single writer: the config lives on a ReadWriteOnce volume, so one replica, recreated.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='plex',
  image='lscr.io/linuxserver/plex:1.41.3',
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
  + kurly.port(32400)
  + kurly.servicePort(32400)
  + kurly.env({ PUID: std.toString(puid), PGID: std.toString(pgid), TZ: timezone, VERSION: 'docker' } + env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/config', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/identity', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
