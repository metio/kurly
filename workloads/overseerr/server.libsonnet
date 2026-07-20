// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// overseerr — a An Overseerr server server (a request-management and media-discovery companion for Plex, integrating with Sonarr and Radarr). A plain composable kurly.http workload on the official
// image; its SQLite configuration and database live on a PersistentVolume. Import it and
// render with kurly.list:
//
//   local overseerr = import 'github.com/metio/kurly/workloads/overseerr/server.libsonnet';
//   kurly.list(overseerr())
//
// Serves the web app and API on :5055 — compose an exposure onto it.
//
// Single writer: the config lives on a ReadWriteOnce volume, so one replica, recreated
// (never rolled) to keep two pods off the SQLite database.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='overseerr',
  image='docker.io/sctx/overseerr:1.35.0',
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
  + kurly.port(5055)
  + kurly.servicePort(5055)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/app/config', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/api/v1/status', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
