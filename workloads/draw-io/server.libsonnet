// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// draw-io — a diagrams.net (draw.io) server (a self-hosted, client-side diagram editor). A plain
// composable kurly.http workload on the official image. The editor runs entirely in the browser;
// the server only serves static assets and a stateless export/proxy endpoint, so it holds no data
// — a plain, horizontally scalable Deployment. Import it and render with kurly.list:
//
//   local drawio = import 'github.com/metio/kurly/workloads/draw-io/server.libsonnet';
//   kurly.list(drawio())
//
// Serves the web app on :8080 — compose an exposure onto it. Diagrams are saved wherever the user
// chooses (browser, their own Google Drive/OneDrive/GitHub); the server keeps nothing.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='draw-io',
  image='docker.io/jgraph/drawio:latest@sha256:51adba39a4a13cd0cb2979916ea9ee6e4438564e76acd51f92e79fc65e728b73',
  replicas=2,
  env={},
  resources={ requests: { cpu: '50m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.scratch('/usr/local/tomcat/temp', '128Mi')
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
