// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mazanoke — a MAZANOKE server (a self-hosted, client-side image optimizer that compresses and
// converts images entirely in the browser). A plain composable kurly.http workload on the official
// image. All processing happens client-side; the server only serves static assets and holds no
// data — a plain, horizontally scalable Deployment. Import it and render with kurly.list:
//
//   local mazanoke = import 'github.com/metio/kurly/workloads/mazanoke/server.libsonnet';
//   kurly.list(mazanoke())
//
// Serves the web app on :80 — compose an exposure onto it. Images never leave the browser.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='mazanoke',
  image='ghcr.io/civilblur/mazanoke:latest@sha256:92cc7474deb789af6549318563b7a9ee750131f9f7b297cc9c87ab67e656c22c',
  replicas=2,
  env={},
  resources={ requests: { cpu: '25m', memory: '32Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env(env)
  + kurly.runAs(101, gid=101, fsGroup=101)
  + kurly.writableRootFilesystem()
  + kurly.scratch('/tmp', '32Mi')
  + kurly.scratch('/var/cache/nginx', '32Mi')
  + kurly.scratch('/var/run', '8Mi')
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
