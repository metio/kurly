// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// homebox — a Homebox server (a simple home/household inventory and asset
// manager). A plain composable kurly.http workload on the ROOTLESS image: it keeps
// its inventory in a SQLite database and uploaded attachments on a PersistentVolume,
// so it needs no external database. Import it and render with kurly.list:
//
//   local homebox = import 'github.com/metio/kurly/workloads/homebox/server.libsonnet';
//   kurly.list(homebox())
//
// Serves the web UI and API on :7745 — compose an exposure onto it.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='homebox',
  image='ghcr.io/sysadminsmedia/homebox:0.26.2-rootless',
  storageSize='2Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(7745)
  + kurly.servicePort(7745)
  + kurly.env({
    HBOX_STORAGE_DATA: '/data',
    HBOX_STORAGE_SQLITE_URL: '/data/homebox.db?_pragma=busy_timeout=1000&_fk=1',
  } + env)
  // A static Go binary, uid-agnostic; pin a non-root uid and its fsGroup so the
  // data volume is writable and the restricted posture admits the pod.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ httpGet: { path: '/api/v1/status', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/v1/status', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
