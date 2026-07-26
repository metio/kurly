// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// tautulli — a Tautulli server (a monitoring and tracking tool for Plex Media Server: history, statistics and notifications). A plain composable kurly.http workload on the
// LinuxServer.io image; its application config (SQLite) lives on a PersistentVolume.
// Import it and render with kurly.list:
//
//   local tautulli = import 'github.com/metio/kurly/workloads/tautulli/server.libsonnet';
//   kurly.list(tautulli())
//
// Serves the web app on :8181 — compose an exposure onto it.
//
// LINUXSERVER IMAGE: the s6-overlay init runs as root and drops to the PUID/PGID user,
// so this runs as root with a writable root filesystem — kurly keeps the rest of the
// hardening (dropped capabilities, seccomp, no privilege escalation, resource limits).
// Set puid/pgid to own the mounted files.
//
// Single writer: the config lives on a ReadWriteOnce volume, so one replica, recreated.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='tautulli',
  image=defaultImage,
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
  + kurly.port(8181)
  + kurly.servicePort(8181)
  + kurly.env({ PUID: std.toString(puid), PGID: std.toString(pgid), TZ: timezone } + env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  // The LinuxServer.io s6-overlay init starts as root and drops to PUID/PGID,
  // so it needs to gain privileges and keep the SETUID/SETGID capabilities.
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  + kurly.store('/config', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
