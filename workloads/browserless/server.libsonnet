// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// browserless — a Browserless server (a headless-Chromium service exposing a REST/WebSocket
// API for rendering, screenshots, PDF generation and scraping — Puppeteer/Playwright as a
// service). A plain composable kurly.http workload on the official image. Each request runs
// a short-lived browser session, so it keeps no state — a plain stateless Deployment. It is
// the browser companion apps like changedetection and karakeep expect. Import it and render
// with kurly.list:
//
//   local browserless = import 'github.com/metio/kurly/workloads/browserless/server.libsonnet';
//   kurly.list(browserless())
//
// Serves its API on :3000 — usually reached in-cluster (http://browserless:3000).
//
// SECRET: browserless gates access with a TOKEN. kurly authors no Secret; provide one
// holding it, pulled in via envFrom.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='browserless',
  image='ghcr.io/browserless/chromium:v2.24.3',
  replicas=2,
  secretName='browserless-secrets',
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.envFromSecret(secretName)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.scratch('/tmp', '512Mi')
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
