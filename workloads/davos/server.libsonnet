// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// davos — a a davos server (a self-hosted FTP automation tool that watches remote directories and downloads on a schedule). A plain composable kurly.http workload on the LinuxServer.io
// image; its application config lives on a PersistentVolume. Import it and render with
// kurly.list:
//
//   local davos = import 'github.com/metio/kurly/workloads/davos/server.libsonnet';
//   kurly.list(davos())
//
// Serves the web app on :8080 — compose an exposure onto it.
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
  name='davos',
  image=defaultImage,
  storageSize='2Gi',
  storageClass=null,
  puid=1000,
  pgid=1000,
  timezone='UTC',
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env({ PUID: std.toString(puid), PGID: std.toString(pgid), TZ: timezone } + env)
  + kurly.rootUser()
  // Writes under /run; a scratch there keeps the rest of the root filesystem read-only.
  + kurly.scratch('/run')
  // The LinuxServer.io s6-overlay init starts as root and drops to PUID/PGID,
  // so it needs to gain privileges and keep the SETUID/SETGID capabilities.
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  + kurly.store('/config', storageSize, storageClass=storageClass)
  // The Spring app takes a while to bring its context up on first start; the
  // startup probe holds the liveness probe off until it binds.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 30 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
