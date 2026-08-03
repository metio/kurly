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
local defaultImage = std.rstripChars(importstr './server.image', '\n');
function(
  name='cyberchef',
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
  // The image's nginx serves the static app on :80; the Service keeps :8000, so
  // an exposure composed onto this workload is unaffected.
  + kurly.port(80)
  + kurly.servicePort(8000)
  + kurly.env(env)
  // The image declares root, but it runs as an ordinary uid: its files are
  // world-readable and everything it writes is under a volume fsGroup owns.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // Writes under /var/cache/nginx; a scratch there keeps the rest of the root filesystem read-only.
  + kurly.scratch('/var/cache/nginx')
  // Writes under /var/run; a scratch there keeps the rest of the root filesystem read-only.
  + kurly.scratch('/var/run')
  // nginx starts as root and hands its cache and temp directories to the nginx
  // Everything is dropped and these are granted back by name — the
  // smallest set this image was observed to boot with.
  + kurly.addCapabilities(['CHOWN', 'SETGID', 'SETUID'])
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
