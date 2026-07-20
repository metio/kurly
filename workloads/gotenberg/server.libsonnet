// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// gotenberg — a Gotenberg server (a stateless API for converting HTML, Markdown and Office
// documents to PDF, and for merging and manipulating PDFs, powered by Chromium and
// LibreOffice). A plain composable kurly.http workload on the official image. It keeps no
// state — each request converts the uploaded document — so it is a plain stateless
// Deployment. It is the PDF-conversion companion apps like paperless-ngx and DocuSeal expect.
// Import it and render with kurly.list:
//
//   local gotenberg = import 'github.com/metio/kurly/workloads/gotenberg/server.libsonnet';
//   kurly.list(gotenberg())
//
// Serves its conversion API on :3000 — usually reached in-cluster (http://gotenberg:3000).
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='gotenberg',
  image='docker.io/gotenberg/gotenberg:8.15.3',
  replicas=2,
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.scratch('/tmp', '512Mi')
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
