// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// ghostfolio — a Ghostfolio server (a self-hosted, open-source wealth-management and portfolio
// tracker for stocks, ETFs, crypto and more). A plain composable kurly.http workload on the
// official image, backed by an external PostgreSQL and Redis. Import it, point it at its backends,
// and render with kurly.list:
//
//   local ghostfolio = import 'github.com/metio/kurly/workloads/ghostfolio/server.libsonnet';
//   kurly.list(ghostfolio())
//
// Serves the web app and API on :3333 — compose an exposure onto it.
//
// BACKENDS & SECRETS: Ghostfolio reads DATABASE_URL, REDIS_HOST/REDIS_PORT/REDIS_PASSWORD,
// ACCESS_TOKEN_SALT and JWT_SECRET_KEY from the environment. kurly authors no Secret; provide one
// holding them, via envFrom. The defaults pair with a cnpg-cluster named ghostfolio-db and a Redis.
//
// Stateless: a plain rolling Deployment.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='ghostfolio',
  image='docker.io/ghostfolio/ghostfolio:latest@sha256:969327948d76b31251237e04842939d01956e278be273a1851f626ade5f10601',
  replicas=2,
  secretName='ghostfolio-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(3333)
  + kurly.servicePort(3333)
  + kurly.envFromSecret(secretName)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.scratch('/tmp', '128Mi')
  + kurly.readinessProbe({ httpGet: { path: '/api/v1/health', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
