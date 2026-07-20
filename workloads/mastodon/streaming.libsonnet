// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mastodon (streaming) — the Mastodon streaming server: a Node.js service that pushes real-time
// timeline and notification updates over WebSockets, for Mastodon (the self-hosted Fediverse
// microblogging platform). A plain composable kurly.http workload on the dedicated streaming
// image, sharing Mastodon's PostgreSQL, Redis and Secret. Import it and render with kurly.list:
//
//   local streaming = import 'github.com/metio/kurly/workloads/mastodon/streaming.libsonnet';
//   kurly.list(streaming())
//
// Serves the streaming API on :4000 — the reverse proxy routes /api/v1/streaming to it.
//
// It reads the same PostgreSQL/Redis connection and secrets as the web stage from the shared
// Secret via envFrom. Stateless — scale freely.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='mastodon-streaming',
  image='ghcr.io/mastodon/mastodon-streaming:v4.3.1',
  replicas=2,
  secretName='mastodon-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(4000)
  + kurly.servicePort(4000)
  + kurly.envFromSecret(secretName)
  + kurly.env({ RAILS_ENV: 'production' } + env)
  + kurly.runAs(991, gid=991, fsGroup=991)
  + kurly.writableRootFilesystem()
  + kurly.readinessProbe({ httpGet: { path: '/api/v1/streaming/health', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
