// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// kanboard — a Kanboard server (a minimalist kanban project-management board). A
// plain composable kurly.http workload on the official image: it keeps its board
// data in a SQLite database and uploaded files on a PersistentVolume by default,
// so it needs no external database. Import it and render with kurly.list:
//
//   local kanboard = import 'github.com/metio/kurly/workloads/kanboard/server.libsonnet';
//   kurly.list(kanboard())
//
// Serves the web UI on :80 — compose an exposure onto it. Point it at an external
// PostgreSQL through env (DATABASE_URL) to scale past the single SQLite writer.
//
// The nginx + PHP-FPM image starts as root and binds :80, so this relaxes kurly's
// non-root and read-only-rootfs defaults while keeping dropped capabilities and no
// privilege escalation.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='kanboard',
  image='docker.io/kanboard/kanboard:v1.2.52',
  storageSize='2Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + (if env == {} then {} else kurly.env(env))
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/var/www/app/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
