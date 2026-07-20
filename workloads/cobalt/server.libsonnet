// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// cobalt — a cobalt API server (a self-hosted media-downloader backend: give it a link and it
// returns a clean download for supported sites). A plain composable kurly.http workload on the
// official image. The API is stateless — it streams and re-muxes on demand and keeps nothing — so
// a plain, horizontally scalable Deployment. Import it, configure it, and render with kurly.list:
//
//   local cobalt = import 'github.com/metio/kurly/workloads/cobalt/server.libsonnet';
//   kurly.list(cobalt(apiUrl='https://cobalt-api.example.com'))
//
// Serves the API on :9000 — compose an exposure onto it. This is the API only; run a cobalt web
// frontend separately if you want the UI.
//
// CONFIGURATION: cobalt reads API_URL (its own public URL, required) and its optional tuning and
// auth settings from the environment. Provide any secret tokens through a Secret referenced with
// your own envFrom (compose kurly.envFromSecret on).
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='cobalt',
  image='ghcr.io/imputnet/cobalt:10@sha256:e5d3fff05a0a5a24ef31b034736fa5075ba45bdb051da1910b84be1c7798f5b4',
  replicas=2,
  apiUrl=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = if apiUrl == null then {} else { API_URL: apiUrl };
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(9000)
  + kurly.servicePort(9000)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.scratch('/tmp', '512Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
