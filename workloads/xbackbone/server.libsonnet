// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// xbackbone — an XBackBone server (a lightweight file and screenshot host with ShareX
// support) on the maintained LinuxServer image. A plain composable kurly.http workload:
// uploads, the SQLite database and the generated configuration all live under /config on
// a PersistentVolume, so it needs no external database. Import it, adapt with the
// parameters below, and render with kurly.list:
//
//   local xbackbone = import 'github.com/metio/kurly/workloads/xbackbone/server.libsonnet';
//   kurly.list(xbackbone())
//
// Serves the web app on :80 — compose an exposure onto it.
//
// LINUXSERVER IMAGE: the s6-overlay init runs as root and drops to the PUID/PGID user,
// so this runs as root with a writable root filesystem — kurly keeps the rest of the
// hardening (dropped capabilities, seccomp, no privilege escalation, resource limits).
// Set puid/pgid to own the mounted files.
//
// Single writer: uploads and the SQLite database live on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='xbackbone',
  image=defaultImage,
  storageSize='20Gi',
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
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env({ PUID: std.toString(puid), PGID: std.toString(pgid), TZ: timezone } + env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  // Everything is dropped and these are granted back by name — the
  // smallest set this image was observed to boot with.
  + kurly.addCapabilities(['CHOWN', 'DAC_OVERRIDE', 'FOWNER', 'FSETID', 'KILL', 'SETGID', 'SETUID', 'SETPCAP'])
  + kurly.store('/config', storageSize, storageClass=storageClass)
  // The installer redirects and the app validates its own base URL, so probe by
  // connection rather than following a redirect into a 4xx.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
