// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// calibre-web — a Calibre-Web server (a clean web interface for browsing, reading and
// downloading books from an existing Calibre library). A plain composable kurly.http
// workload on the LinuxServer.io image; its application config (SQLite) lives on a
// PersistentVolume. Import it, adapt with the parameters below, and render with
// kurly.list:
//
//   local calibreWeb = import 'github.com/metio/kurly/workloads/calibre-web/server.libsonnet';
//   kurly.list(calibreWeb())
//
// Serves the web app on :8083 — compose an exposure onto it.
//
// LIBRARY: Calibre-Web reads an existing Calibre library (the directory holding
// metadata.db). Mount it and point Calibre-Web at it on first run; compose an extra
// volume for it, or keep the library under the config volume.
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
  name='calibre-web',
  image='lscr.io/linuxserver/calibre-web:0.6.26',
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
  + kurly.port(8083)
  + kurly.servicePort(8083)
  + kurly.env({ PUID: std.toString(puid), PGID: std.toString(pgid), TZ: timezone } + env)
  // The s6-overlay init needs root and a writable root filesystem; it drops to PUID.
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/config', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
