// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// radicale — a Radicale server (a lightweight CalDAV and CardDAV server for
// calendars and contacts). A plain composable kurly.http workload on the
// well-maintained tomsquest image: it keeps its collections on a PersistentVolume,
// so it needs no external database. Import it and render with kurly.list:
//
//   local radicale = import 'github.com/metio/kurly/workloads/radicale/server.libsonnet';
//   kurly.list(radicale())
//
// Serves CalDAV/CardDAV on :5232 — compose an exposure onto it.
//
// AUTHENTICATION: the default configuration allows anonymous access. For real use,
// mount a Radicale config and an htpasswd users file (a Secret — kurly mints none)
// with kurly.config / kurly.secretMount, and set auth to htpasswd.
//
// Single writer: the collections live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
//
// The image runs its s6 init as its designated uid 2999 and writes to the root
// filesystem, so this pins that uid and relaxes the read-only-rootfs default while
// keeping non-root, dropped capabilities, and no privilege escalation.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='radicale',
  image='docker.io/tomsquest/docker-radicale:3.7.6.0',
  storageSize='2Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '25m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(5232)
  + kurly.servicePort(5232)
  + (if env == {} then {} else kurly.env(env))
  + kurly.runAs(2999, gid=2999, fsGroup=2999)
  + kurly.writableRootFilesystem()
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
