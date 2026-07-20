// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// lemmy (ui) — the Lemmy web frontend: the server-rendered web app users load, which talks to the
// Lemmy backend. The user-facing stage of Lemmy (the self-hosted Fediverse link aggregator).
// Import it and render with kurly.list:
//
//   local ui = import 'github.com/metio/kurly/workloads/lemmy/ui.libsonnet';
//   kurly.list(ui(externalHost='lemmy.example.com'))
//
// Serves the web app on :1234 — compose an exposure onto it.
//
// It reaches the backend by its in-cluster Service name through internalHost; set externalHost to
// your public domain. It is stateless, so it scales freely.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='lemmy-ui',
  image='docker.io/dessalines/lemmy-ui:0.19.7',
  replicas=2,
  internalHost='lemmy:8536',
  externalHost=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  local baseEnv =
    { LEMMY_UI_LEMMY_INTERNAL_HOST: internalHost, LEMMY_UI_HTTPS: 'true' }
    + (if externalHost == null then {} else { LEMMY_UI_LEMMY_EXTERNAL_HOST: externalHost });
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(1234)
  + kurly.servicePort(1234)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
