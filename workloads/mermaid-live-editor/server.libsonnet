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
function(
  name='mermaid-live-editor',
  image='ghcr.io/mermaid-js/mermaid-live-editor:latest@sha256:836616adc144fdc0f711a8fb149cc572eed63fe4de347c2ab6448831c8992c28',
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
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.scratch('/tmp', '32Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
