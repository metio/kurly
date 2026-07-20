// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// owncast — an Owncast server (a self-hosted live video streaming and chat server, an
// open alternative to Twitch: you stream to it over RTMP and viewers watch on your own
// site). A plain composable kurly.http workload on the official image; its data (SQLite
// config, chat history, and stream segments) lives on a PersistentVolume. Import it,
// adapt with the parameters below, and render with kurly.list:
//
//   local owncast = import 'github.com/metio/kurly/workloads/owncast/server.libsonnet';
//   kurly.list(owncast())
//
// Serves the web player and API on :8080 — compose an exposure onto it.
//
// RTMP INGEST: streaming INTO Owncast uses RTMP on :1935, a separate port this HTTP
// workload does not expose. Add a Service for it (a raw `+` patch, or a dedicated
// LoadBalancer) so your broadcaster can reach it; the web player works without it.
//
// Single writer: the data lives on a ReadWriteOnce volume, so one replica, recreated
// (never rolled) to keep two pods off the SQLite database and segments.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='owncast',
  image='docker.io/owncast/owncast:0.2.5',
  storageSize='20Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '250m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/app/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/api/status', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/status', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
