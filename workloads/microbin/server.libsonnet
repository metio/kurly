// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// microbin — a MicroBin server (a tiny, self-contained pastebin and file-sharing
// service). A plain composable kurly.http workload: it keeps its pastes and
// uploaded files on a PersistentVolume, so it needs no external database. Import it
// and render with kurly.list:
//
//   local microbin = import 'github.com/metio/kurly/workloads/microbin/server.libsonnet';
//   kurly.list(microbin())
//
// Serves the web UI and API on :8080 — compose an exposure onto it.
//
// Single writer: the pastes and files live on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='microbin',
  image='docker.io/danielszabo99/microbin:v2.1.4',
  storageSize='1Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '25m', memory: '32Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env({ MICROBIN_PORT: '8080', MICROBIN_BIND: '0.0.0.0', MICROBIN_DATA_DIR: '/app/microbin_data' } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/app/microbin_data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '32Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
