// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// it-tools — an IT-Tools server (a large collection of handy online tools for developers
// and sysadmins: encoders, converters, generators, formatters and more, all client-side).
// A plain composable kurly.http workload on the official image. It serves a static app
// and keeps no state, so it is a plain stateless Deployment. Import it and render with
// kurly.list:
//
//   local itTools = import 'github.com/metio/kurly/workloads/it-tools/server.libsonnet';
//   kurly.list(itTools())
//
// Serves the app on :80 — compose an exposure onto it.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='it-tools',
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
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env(env)
  // The image declares root, but it runs as an ordinary uid: its files are
  // world-readable and everything it writes is under a volume fsGroup owns.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // Writes under /var/cache/nginx; a scratch there keeps the rest of the root filesystem read-only.
  + kurly.scratch('/var/cache/nginx')
  // Writes under /var/run; a scratch there keeps the rest of the root filesystem read-only.
  + kurly.scratch('/var/run')
  // The bundled nginx starts as root and chowns its cache dir to the worker
  // Everything is dropped and these are granted back by name — the
  // smallest set this image was observed to boot with.
  + kurly.addCapabilities(['CHOWN', 'SETGID', 'SETUID'])
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
