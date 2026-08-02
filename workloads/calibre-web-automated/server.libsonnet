// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// calibre-web-automated — a Calibre-Web Automated server (a self-hosted web reader and library
// manager for a Calibre ebook library, adding automatic ingest and format conversion on top of
// Calibre-Web). A plain composable kurly.http workload on the LinuxServer.io-based image; its
// application config lives on one PersistentVolume and the Calibre library on another. Import it,
// adapt with the parameters below, and render with kurly.list:
//
//   local cwa = import 'github.com/metio/kurly/workloads/calibre-web-automated/server.libsonnet';
//   kurly.list(cwa())
//
// Serves the web app on :8083 — compose an exposure onto it.
//
// LINUXSERVER IMAGE: the s6-overlay init runs as root and drops to the PUID/PGID user, so this
// runs as root with a writable root filesystem and keeps the SETUID/SETGID/CHOWN capabilities it
// needs to hand the library to that user — kurly keeps the rest of the hardening (seccomp,
// resource limits). Set puid/pgid to own the mounted files.
//
// Single writer: config and library live on ReadWriteOnce volumes, so one replica, recreated.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');
function(
  name='calibre-web-automated',
  image=defaultImage,
  configSize='1Gi',
  librarySize='20Gi',
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
  + kurly.port(8083)
  + kurly.servicePort(8083)
  + kurly.env({ PUID: std.toString(puid), PGID: std.toString(pgid), TZ: timezone } + env)
  + kurly.rootUser()
  // Writes under /run; a scratch there keeps the rest of the root filesystem read-only.
  + kurly.scratch('/run')
  // The s6-overlay init starts as root and drops to PUID/PGID, and the ingest service
  // chowns the mounted library, so it needs to gain privileges and keep SETUID/SETGID/CHOWN.
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  + kurly.store('/config', configSize, storageClass=storageClass)
  + kurly.store('/calibre-library', librarySize, storageClass=storageClass)
  // Unpacking the bundled Calibre binaries takes minutes on a cold volume — gate the
  // liveness probe until the web app binds.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 60 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
