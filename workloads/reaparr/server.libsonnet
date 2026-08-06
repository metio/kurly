// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// reaparr — a Reaparr server (points at Plex servers you have access to and copies
// the media you pick from them into your own library). A plain composable
// kurly.http workload; its SQLite database and settings live on a PersistentVolume.
// Import it and render with kurly.list:
//
//   local reaparr = import 'github.com/metio/kurly/workloads/reaparr/server.libsonnet';
//   kurly.list(reaparr())
//
// Serves the web app and its API on :7000 — compose an exposure onto it.
//
// LIBRARY PATHS: Reaparr downloads into /Downloads and moves finished media into
// /Movies and /TvShows. Those are ordinary directories here — mount the volumes your
// library really lives on over them, or leave them inside the container and lose the
// media with the pod. Only /Config is persisted by default.
//
// PLEX CREDENTIALS are entered in the web UI and stored in the /Config database;
// kurly authors no Secret for them.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='reaparr',
  image=defaultImage,
  // The SQLite database, settings and logs.
  storageSize='5Gi',
  storageClass=null,
  timezone='UTC',
  logLevel='INFORMATION',
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(7000)
  + kurly.servicePort(7000)
  + kurly.env({ TZ: timezone, LOG_LEVEL: logLevel } + env)
  // The image ships USER abc (uid 911 in the LinuxServer base image) and its s6
  // service execs the application as that account, so nothing here needs root. The
  // uid is pinned so the volume is group-owned by it and the app can write its
  // database — the s6 init cannot chown it from an unprivileged user.
  + kurly.runAs(911, 911)
  // s6-overlay assembles its service tree under /run and /var/run at every start,
  // and the .NET runtime keeps its temporary files in /tmp.
  + kurly.scratch('/run')
  + kurly.scratch('/var/run')
  + kurly.scratch('/tmp')
  + kurly.store('/Config', storageSize, storageClass=storageClass)
  // A .NET application behind a first-run database migration: give it room to come
  // up before the liveness probe starts counting.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
