// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// syncthing — a a Syncthing server (a continuous, self-hosted file-synchronization tool that syncs folders between devices peer-to-peer). A plain composable kurly.http workload on the LinuxServer.io
// image; its application config (SQLite) lives on a PersistentVolume. Import it and render
// with kurly.list:
//
//   local syncthing = import 'github.com/metio/kurly/workloads/syncthing/server.libsonnet';
//   kurly.list(syncthing())
//
// Serves the web app on :8384 — compose an exposure onto it.
//
// SYNC: the sync protocol on :22000 (TCP and UDP/QUIC) and local discovery on :21027 (UDP)
// ride onto the Service beside the web port (the 'sync-tcp', 'sync-udp' and 'discovery' ports);
// route them so peers can connect. Mount the folders you sync as extra volumes.
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
  name='syncthing',
  image='lscr.io/linuxserver/syncthing:2.1.2',
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
  + kurly.port(8384)
  + kurly.servicePort(8384)
  + kurly.extraPort('sync-tcp', 22000)
  + kurly.extraPort('sync-udp', 22000, protocol='UDP')
  + kurly.extraPort('discovery', 21027, protocol='UDP')
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
