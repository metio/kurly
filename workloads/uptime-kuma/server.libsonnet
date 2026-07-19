// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// uptime-kuma — an Uptime Kuma monitoring server (self-hosted uptime monitoring
// and status pages). A plain composable kurly.http workload: it keeps its checks,
// history, and settings in a SQLite database on a PersistentVolume, so it needs no
// external database. Import it and render with kurly.list:
//
//   local uptimeKuma = import 'github.com/metio/kurly/workloads/uptime-kuma/server.libsonnet';
//   kurly.list(uptimeKuma())
//
// Serves the dashboard and status pages on :3001 — compose an exposure onto it.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='uptime-kuma',
  image='docker.io/louislam/uptime-kuma:1.23.16',
  storageSize='2Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3001)
  + kurly.servicePort(3001)
  + (if env == {} then {} else kurly.env(env))
  // The image ships no non-root user; pin one and its fsGroup so the data volume
  // is writable and the restricted posture admits the pod.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/app/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
