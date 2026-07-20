// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// nzbget — a an NZBGet server (an efficient, self-hosted Usenet downloader written in C++). A plain composable kurly.http workload on the LinuxServer.io
// image; its application config (SQLite) lives on a PersistentVolume. Import it and render
// with kurly.list:
//
//   local nzbget = import 'github.com/metio/kurly/workloads/nzbget/server.libsonnet';
//   kurly.list(nzbget())
//
// Serves the web app on :6789 — compose an exposure onto it.
//
// DOWNLOADS & MEDIA: mount your downloads (and media/watch) directories and point the app
// at them in its settings; compose the extra volumes on. The config volume holds only the
// app's own state.
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
  name='nzbget',
  image='lscr.io/linuxserver/nzbget:26.2.20260717',
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
  + kurly.port(6789)
  + kurly.servicePort(6789)
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
