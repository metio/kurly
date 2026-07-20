// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// drawio — a draw.io / diagrams.net server (the self-hosted web editor for flowcharts,
// UML, network diagrams and more). A plain composable kurly.http workload on the official
// image. The editor runs entirely in the browser and stores diagrams wherever the user
// chooses (device, Git, cloud), so the server keeps no state — a plain stateless
// Deployment. Import it and render with kurly.list:
//
//   local drawio = import 'github.com/metio/kurly/workloads/drawio/server.libsonnet';
//   kurly.list(drawio())
//
// Serves the editor on :8080 — compose an exposure onto it.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='drawio',
  image='docker.io/jgraph/drawio:v30.3.14',
  replicas=2,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env(env)
  // The bundled Tomcat starts as root; the root filesystem stays writable for its work
  // and temp directories.
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
