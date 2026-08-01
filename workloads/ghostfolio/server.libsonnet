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
local defaultImage = std.rstripChars(importstr './server.image', '\n');
function(
  name='ghostfolio',
  image=defaultImage,
  replicas=2,
  // The Redis it queues jobs and caches market data in. It is named after the
  // convention kurly's valkey workload follows, so a default deployment connects
  // with no override; the password comes from the Secret.
  redisHost='ghostfolio-cache-headless',
  redisPort=6379,
  secretName='ghostfolio',
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
  + kurly.env({ REDIS_HOST: redisHost, REDIS_PORT: std.toString(redisPort) } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.scratch('/tmp', '128Mi')
  // Kept as UNVERIFIABLE rather than needed: ghostfolio never becomes ready on this
  // host, with zero restarts and no container output at all, so a read-only root
  // filesystem here would be a claim nothing tested. Its boot produced no read-only
  // error, so this may well come off — but only once the workload can be booted to
  // show it.
  + kurly.writableRootFilesystem()
  + kurly.readinessProbe({ httpGet: { path: '/api/v1/health', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
