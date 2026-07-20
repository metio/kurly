// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// jellyfin — a a Jellyfin server (a free, self-hosted media server for streaming your movies, shows and music). A plain composable kurly.http workload on the LinuxServer.io
// image; its application config (SQLite) lives on a PersistentVolume. Import it and render
// with kurly.list:
//
//   local jellyfin = import 'github.com/metio/kurly/workloads/jellyfin/server.libsonnet';
//   kurly.list(jellyfin())
//
// Serves the web app on :8096 — compose an exposure onto it.
//
// MEDIA: mount your media libraries (read-only is fine) and add them as libraries in the
// UI; compose the extra volumes on. The config volume holds only the app's own state.
//
// LINUXSERVER IMAGE: the s6-overlay init runs as root and drops to the PUID/PGID user,
// so this runs as root with a writable root filesystem — kurly keeps the rest of the
// hardening (dropped capabilities, seccomp, no privilege escalation, resource limits).
// Set puid/pgid to own the mounted files.
//
// Single writer: the config lives on a ReadWriteOnce volume, so one replica, recreated.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='jellyfin',
  image='lscr.io/linuxserver/jellyfin:10.11.11',
  storageSize='10Gi',
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
  + kurly.port(8096)
  + kurly.servicePort(8096)
  + kurly.env({ PUID: std.toString(puid), PGID: std.toString(pgid), TZ: timezone } + env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/config', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
