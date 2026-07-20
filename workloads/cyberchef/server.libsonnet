// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// cyberchef — a CyberChef server (GCHQ's "cyber Swiss-army knife": a web app for encoding,
// encryption, compression and data analysis, all in the browser). A plain composable
// kurly.http workload on the official image. It serves a static app and keeps no state, so
// it is a plain stateless Deployment. Import it and render with kurly.list:
//
//   local cyberchef = import 'github.com/metio/kurly/workloads/cyberchef/server.libsonnet';
//   kurly.list(cyberchef())
//
// Serves the app on :8000 — compose an exposure onto it.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='cyberchef',
  image='ghcr.io/gchq/cyberchef:10.19.4',
  replicas=2,
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8000)
  + kurly.servicePort(8000)
  + kurly.env(env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
