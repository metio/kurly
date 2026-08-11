// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// docling-serve — an HTTP API around Docling, which converts PDFs, Office
// documents, HTML and images into structured Markdown or JSON. A plain composable
// kurly.http workload: each request is converted and returned, nothing is kept,
// so it claims no volume and any replica count is safe. Import it and render with
// kurly.list:
//
//   local docling = import 'github.com/metio/kurly/workloads/docling-serve/server.libsonnet';
//   kurly.list(docling())
//
// Serves the API on :5001 — compose an exposure onto it.
//
// MEMORY, NOT CPU, IS THE LIMIT. Conversion loads layout and table models and
// holds a whole document in memory while it works; the default limit here is
// sized for that rather than for an idle process, and a large scanned PDF will
// want more. A container killed mid-conversion looks like an application crash
// and is a memory limit.
//
// MODELS: the image ships the default model set. `enableUi` turns on the bundled
// Gradio interface, which is off by default because it is a second, unauthenticated
// way in.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='docling-serve',
  image=defaultImage,
  replicas=1,
  // The bundled Gradio interface at /ui — a second way in, so opt-in.
  enableUi=false,
  env={},
  resources={ requests: { cpu: '500m', memory: '2Gi' }, limits: { memory: '4Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(5001)
  + kurly.servicePort(5001)
  + kurly.env(
    {
      DOCLING_SERVE_HOST: '0.0.0.0',
      DOCLING_SERVE_PORT: '5001',
      DOCLING_SERVE_ENABLE_UI: if enableUi then 'true' else 'false',
    } + env
  )
  // The uid the image already runs as.
  + kurly.runAs(1001, gid=0)
  // Conversion unpacks archives and buffers pages under the home directory and
  // /tmp, both of which are inside the read-only image tree.
  + kurly.scratch('/tmp', '2Gi')
  + kurly.scratch('/opt/app-root/src/.cache', '1Gi')
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
