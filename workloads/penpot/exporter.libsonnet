// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// penpot (exporter) — the Penpot exporter: a headless-browser service that renders boards and
// files to PNG/PDF/SVG for Penpot (the self-hosted, open-source Figma alternative). A plain
// composable kurly.worker exposed on :6061, sharing Penpot's Redis and Secret. Import it and
// render with kurly.list:
//
//   local exporter = import 'github.com/metio/kurly/workloads/penpot/exporter.libsonnet';
//   kurly.list(exporter())
//
// Serves on :6061 — the frontend reaches it at http://penpot-exporter:6061.
//
// It reads PENPOT_PUBLIC_URI (the backend) and PENPOT_REDIS_URI from the shared Secret via
// envFrom. Stateless; it runs a headless browser, so it wants a little scratch space.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='penpot-exporter',
  image='docker.io/penpotapp/exporter:2.3.2',
  replicas=1,
  secretName='penpot-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(6061)
  + kurly.servicePort(6061)
  + kurly.envFromSecret(secretName)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.scratch('/tmp', '256Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
