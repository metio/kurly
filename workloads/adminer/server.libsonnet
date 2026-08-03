// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// adminer — an Adminer server (a full-featured database management tool in a single PHP
// file: connect to MySQL, PostgreSQL, SQLite and more from the browser). A plain composable
// kurly.http workload on the official image. It holds no state — it connects to whatever
// database you point it at — so it is a plain stateless Deployment. Import it and render
// with kurly.list:
//
//   local adminer = import 'github.com/metio/kurly/workloads/adminer/server.libsonnet';
//   kurly.list(adminer())
//
// Serves the web app on :8080 — compose an exposure onto it.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');
function(
  name='adminer',
  image=defaultImage,
  replicas=2,
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env(env)
  // The image declares root, but it runs as an ordinary uid: its files are
  // world-readable and everything it writes is under a volume fsGroup owns.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
