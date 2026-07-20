// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// ombi — a An Ombi server (a request-management portal for Plex, Emby and Jellyfin, letting users ask for new media). A plain composable kurly.http workload on the
// LinuxServer.io image; its application config (SQLite) lives on a PersistentVolume.
// Import it and render with kurly.list:
//
//   local ombi = import 'github.com/metio/kurly/workloads/ombi/server.libsonnet';
//   kurly.list(ombi())
//
// Serves the web app on :3579 — compose an exposure onto it.
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
  name='ombi',
  image='lscr.io/linuxserver/ombi:4.53.10',
  storageSize='1Gi',
  storageClass=null,
  puid=1000,
  pgid=1000,
  timezone='UTC',
  env={},
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3579)
  + kurly.servicePort(3579)
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
