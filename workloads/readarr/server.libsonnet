// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// readarr — a Readarr server (an ebook and audiobook collection manager for Usenet and BitTorrent
// users). A plain composable kurly.http workload on the LinuxServer.io image; its application
// config (SQLite) lives on a PersistentVolume. Import it, adapt with the parameters below, and
// render with kurly.list:
//
//   local readarr = import 'github.com/metio/kurly/workloads/readarr/server.libsonnet';
//   kurly.list(readarr())
//
// Serves the web app and API on :8787 — compose an exposure onto it.
//
// MEDIA & DOWNLOADS: Readarr works against your library and download-client directories. Mount
// them and point Readarr at them in its settings; compose the extra volumes on, or keep them under
// the config volume.
//
// LINUXSERVER IMAGE: the s6-overlay init runs as root and drops to the PUID/PGID user, so this
// runs as root with a writable root filesystem — kurly keeps the rest of the hardening (dropped
// capabilities, seccomp, no privilege escalation, resource limits). Set puid/pgid to own the
// mounted files.
//
// Single writer: the config lives on a ReadWriteOnce volume, so one replica, recreated.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='readarr',
  image='ghcr.io/linuxserver/readarr:develop@sha256:eb37f58646a901dc7727cf448cae36daaefaba79de33b5058dab79aa4c04aefb',
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
  + kurly.port(8787)
  + kurly.servicePort(8787)
  + kurly.env({ PUID: std.toString(puid), PGID: std.toString(pgid), TZ: timezone } + env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/config', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
