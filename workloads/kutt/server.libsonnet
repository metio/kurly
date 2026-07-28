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
local defaultImage = std.rstripChars(importstr './server.image', '\n');
function(
  name='kutt',
  image=defaultImage,
  replicas=2,
  // The PostgreSQL and Redis it stores links and rate-limit state in; the database
  // password comes from the Secret.
  dbHost='kutt-db-rw',
  dbPort=5432,
  dbName='kutt',
  dbUser='kutt',
  redisHost='kutt-cache-headless',
  redisPort=6379,
  secretName='kutt',
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
  + kurly.env({
    // knex picks its driver from DB_CLIENT; without it the app falls back to the
    // bundled SQLite file, which has nowhere to live here.
    DB_CLIENT: 'pg',
    DB_HOST: dbHost,
    DB_PORT: std.toString(dbPort),
    DB_DATABASE: dbName,
    DB_USER: dbUser,
    REDIS_HOST: redisHost,
    REDIS_PORT: std.toString(redisPort),
  } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
