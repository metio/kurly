// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// flaresolverr — a FlareSolverr server (a proxy that solves Cloudflare and DDoS-GUARD
// browser challenges by driving a headless browser, so scrapers and the *arr indexers
// can reach protected sites). A plain composable kurly.http workload on the official
// image. It holds no persistent state — each request spins a short-lived browser
// session — so it is a plain stateless Deployment. Import it and render with kurly.list:
//
//   local flaresolverr = import 'github.com/metio/kurly/workloads/flaresolverr/server.libsonnet';
//   kurly.list(flaresolverr())
//
// Serves its solver API on :8191 — other workloads (e.g. Jackett/Prowlarr) point their
// FlareSolverr URL at http://flaresolverr:8191. It is an internal helper, so it usually
// needs no exposure.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='flaresolverr',
  image='ghcr.io/flaresolverr/flaresolverr:v3.5.0',
  replicas=1,
  logLevel='info',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8191)
  + kurly.servicePort(8191)
  + kurly.env({ LOG_LEVEL: logLevel } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  // The bundled headless browser writes to /tmp and needs a larger shared-memory mount
  // than the default 64Mi to render pages without crashing.
  + kurly.scratch('/tmp', '256Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
