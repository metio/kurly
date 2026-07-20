// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// kutt — a Kutt server (a free, self-hosted modern URL shortener with custom domains, link
// analytics and an API). A plain composable kurly.http workload on the official image,
// backed by an external PostgreSQL and Redis. Import it, point it at its backends, and render
// with kurly.list:
//
//   local kutt = import 'github.com/metio/kurly/workloads/kutt/server.libsonnet';
//   kurly.list(kutt())
//
// Serves the web app and API on :3000 — compose an exposure onto it.
//
// BACKENDS & SECRETS: Kutt reads its PostgreSQL and Redis connection, plus JWT_SECRET and the
// DEFAULT_DOMAIN, from the environment. kurly authors no Secret; provide one holding them, via
// envFrom. The defaults pair with a cnpg-cluster named kutt-db and a Redis.
//
// Stateless: links live in PostgreSQL, so this is a plain rolling Deployment.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='kutt',
  image='docker.io/kutt/kutt:v3.2.0',
  replicas=2,
  secretName='kutt-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
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
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
