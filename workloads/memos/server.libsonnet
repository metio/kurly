// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// memos — a Memos server (a lightweight, self-hosted notes and micro-blogging
// service). A plain composable kurly.http workload: it keeps its notes in a SQLite
// database on a PersistentVolume, so it needs no external database. Import it and
// render with kurly.list:
//
//   local memos = import 'github.com/metio/kurly/workloads/memos/server.libsonnet';
//   kurly.list(memos())
//
// Serves the web UI and API on :5230 — compose an exposure onto it.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file. Point MEMOS_DRIVER at
// external PostgreSQL through env to scale past that.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='memos',
  image='docker.io/neosmemo/memos:0.29.1',
  storageSize='1Gi',
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
  + kurly.port(5230)
  + kurly.servicePort(5230)
  + kurly.env({ MEMOS_MODE: 'prod', MEMOS_PORT: '5230', MEMOS_DATA: '/var/opt/memos' } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/var/opt/memos', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '32Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
