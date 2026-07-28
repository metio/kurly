// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// whoogle — a Whoogle Search server (a self-hosted, privacy-respecting metasearch proxy for
// Google results: no ads, no tracking, no JavaScript required). A plain composable
// kurly.http workload on the official image. It holds no state — each query is proxied live
// — so it is a plain stateless Deployment. Import it and render with kurly.list:
//
//   local whoogle = import 'github.com/metio/kurly/workloads/whoogle/server.libsonnet';
//   kurly.list(whoogle())
//
// Serves the search UI on :5000 — compose an exposure onto it. Configure it through
// WHOOGLE_CONFIG_* environment variables (see the project docs).
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');
function(
  name='whoogle',
  image=defaultImage,
  replicas=2,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(5000)
  + kurly.servicePort(5000)
  + kurly.env(env)
  // The image's own whoogle account owns the static tree it builds into on start.
  + kurly.runAs(927, gid=927, fsGroup=927)
  + kurly.writableRootFilesystem()
  + kurly.readinessProbe({ httpGet: { path: '/healthz', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
