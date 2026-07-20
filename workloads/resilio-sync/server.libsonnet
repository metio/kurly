// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// resilio-sync — a a Resilio Sync server (a fast, peer-to-peer file-synchronization tool (BitTorrent-based) with a web UI). A plain composable kurly.http workload on the LinuxServer.io
// image; its application config lives on a PersistentVolume. Import it and render with
// kurly.list:
//
//   local resilio-sync = import 'github.com/metio/kurly/workloads/resilio-sync/server.libsonnet';
//   kurly.list(resilio-sync())
//
// Serves the web app on :8888 — compose an exposure onto it.
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
  name='resilio-sync',
  image='lscr.io/linuxserver/resilio-sync:3.1.2.1076-1-ls251',
  storageSize='5Gi',
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
  + kurly.port(8888)
  + kurly.servicePort(8888)
  + kurly.env({ PUID: std.toString(puid), PGID: std.toString(pgid), TZ: timezone } + env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/config', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
