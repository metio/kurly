// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// fluidd — a Fluidd server (the web interface for Klipper-based 3D printers: job
// queue, temperatures, console and file management). A plain composable kurly.http
// workload on the official image. It serves a static single-page app and keeps no
// state, so it is a plain stateless Deployment. Import it and render with kurly.list:
//
//   local fluidd = import 'github.com/metio/kurly/workloads/fluidd/server.libsonnet';
//   kurly.list(fluidd())
//
// Serves the web app on :80 — compose an exposure onto it.
//
// PRINTER: Fluidd talks to a Moonraker API, which runs on the printer's host beside
// Klipper and is not something a cluster provides. The app asks the browser for that
// endpoint on first load, so the pod itself needs no connection to it; whoever opens
// the page does.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');
function(
  name='fluidd',
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
  // The image declares root, but nginx serves world-readable files and writes
  // nothing outside the scratches below, so an ordinary uid is enough.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // The entrypoint renders /etc/nginx/templates into /etc/nginx/conf.d on every
  // start; a scratch there keeps the rest of the root filesystem read-only.
  + kurly.scratch('/etc/nginx/conf.d')
  // Writes under /var/cache/nginx; a scratch there keeps the rest of the root filesystem read-only.
  + kurly.scratch('/var/cache/nginx')
  // Writes its pid under /var/run; a scratch there keeps the rest of the root filesystem read-only.
  + kurly.scratch('/var/run')
  // Writes under /tmp; a scratch there keeps the rest of the root filesystem read-only.
  + kurly.scratch('/tmp')
  // nginx starts up chowning its cache and temp directories and dropping to its
  // own account. Everything is dropped and these are granted back by name — the
  // smallest set this image was observed to boot with.
  + kurly.addCapabilities(['CHOWN', 'SETGID', 'SETUID'])
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
