// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// pairdrop — a PairDrop server (a self-hosted, AirDrop-style local file-sharing app:
// transfer files and messages between devices over the browser, peer-to-peer via WebRTC).
// A plain composable kurly.http workload on the official image. The server only brokers
// the peer connections and keeps no state, so it is a plain Deployment with no volume.
// Import it and render with kurly.list:
//
//   local pairdrop = import 'github.com/metio/kurly/workloads/pairdrop/server.libsonnet';
//   kurly.list(pairdrop())
//
// Serves the web app and signaling on :3000 — compose an exposure onto it.
//
// One replica: peers pair through in-memory rooms held by a single server instance, so
// running more than one replica without sticky routing would split rooms across pods.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='pairdrop',
  image='ghcr.io/schlagmichdoch/pairdrop:v1.11.2',
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
