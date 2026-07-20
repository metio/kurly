// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// tika — an Apache Tika server (a content-analysis toolkit that detects and extracts text
// and metadata from over a thousand file types — PDFs, Office docs, images and more). A
// plain composable kurly.http workload on the official image. It keeps no state — each
// request extracts from the uploaded document — so it is a plain stateless Deployment. It is
// the text-extraction companion apps like paperless-ngx expect. Import it and render with
// kurly.list:
//
//   local tika = import 'github.com/metio/kurly/workloads/tika/server.libsonnet';
//   kurly.list(tika())
//
// Serves its extraction API on :9998 — usually reached in-cluster (http://tika:9998).
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='tika',
  image='docker.io/apache/tika:2.9.2.1',
  replicas=2,
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(9998)
  + kurly.servicePort(9998)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.scratch('/tmp', '256Mi')
  + kurly.readinessProbe({ httpGet: { path: '/tika', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
