// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// redis-commander — a Redis Commander server (a self-hosted web UI for managing Redis: browse
// keys, run commands and inspect data across one or more Redis instances). A plain composable
// kurly.http workload on the official image. It holds no state — it connects to the Redis you
// point it at — so it is a plain stateless Deployment. Import it, point it at Redis, and render
// with kurly.list:
//
//   local rc = import 'github.com/metio/kurly/workloads/redis-commander/server.libsonnet';
//   kurly.list(rc(redisHosts='local:redis:6379'))
//
// Serves the web app on :8081 — compose an exposure onto it.
//
// The image publishes only a rolling tag, so it is pinned by digest here; Renovate resolves and
// updates the digest.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='redis-commander',
  image='ghcr.io/joeferner/redis-commander:latest@sha256:1ad484c1fc0a3b4072dfa2bb10d44f0eba8ecb342c8c0f9e17cb21a6557e4b7e',
  replicas=2,
  redisHosts=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = if redisHosts == null then {} else { REDIS_HOSTS: redisHosts };
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8081)
  + kurly.servicePort(8081)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
