// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mermaid-live-editor — a Mermaid Live Editor server (a self-hosted, in-browser editor for Mermaid
// diagrams: flowcharts, sequence diagrams, Gantt charts and more from text). A plain composable
// kurly.http workload on the official image. Diagrams are rendered client-side and shared via URL,
// so the server only serves static assets and holds no data — a plain, horizontally scalable
// Deployment. Import it and render with kurly.list:
//
//   local mermaid = import 'github.com/metio/kurly/workloads/mermaid-live-editor/server.libsonnet';
//   kurly.list(mermaid())
//
// Serves the web app on :8080 — compose an exposure onto it.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');
function(
  name='mermaid-live-editor',
  image=defaultImage,
  replicas=2,
  env={},
  resources={ requests: { cpu: '25m', memory: '32Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env(env)
  // nginx starts as root, prepares its cache directories, then drops to the nginx
  // user for the workers.
  + kurly.rootUser()
  // Everything is dropped and these are granted back by name — the
  // smallest set this image was observed to boot with.
  + kurly.addCapabilities(['CHOWN', 'SETGID', 'SETUID'])
  + kurly.scratch('/tmp', '32Mi')
  // nginx creates its temp directories under /var/cache/nginx on start and writes
  // its pid under /var/run. The image ships an empty cache directory, so a scratch
  // there hides nothing — the same trio that lets chatpad serve from a read-only
  // root. (The entrypoint's "can not modify default.conf" line is informational;
  // the cache mkdir is what stops it.)
  + kurly.scratch('/var/cache/nginx', '32Mi')
  + kurly.scratch('/var/run', '8Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
