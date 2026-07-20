// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// chatpad — a Chatpad AI server (a self-hosted, clean web UI for OpenAI's chat models). A plain
// composable kurly.http workload on the official image. Conversations and the API key are stored
// client-side in the browser, so the server only serves static assets and holds no data — a plain,
// horizontally scalable Deployment. Import it and render with kurly.list:
//
//   local chatpad = import 'github.com/metio/kurly/workloads/chatpad/server.libsonnet';
//   kurly.list(chatpad())
//
// Serves the web app on :80 — compose an exposure onto it. The browser talks to OpenAI directly
// with the user's own key.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='chatpad',
  image='ghcr.io/deiucanta/chatpad:latest@sha256:15155e3a09fd677d578583f6bd3848c991cf768997400e37bc4c27e62a918a7e',
  replicas=2,
  env={},
  resources={ requests: { cpu: '25m', memory: '32Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env(env)
  + kurly.runAs(101, gid=101, fsGroup=101)
  + kurly.writableRootFilesystem()
  + kurly.scratch('/tmp', '32Mi')
  + kurly.scratch('/var/cache/nginx', '32Mi')
  + kurly.scratch('/var/run', '8Mi')
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
