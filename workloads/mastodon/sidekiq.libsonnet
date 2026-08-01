// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mastodon (sidekiq) — the Mastodon background worker: it runs the Sidekiq job queues that handle
// federation delivery, media processing, scheduled tasks and more, for Mastodon (the self-hosted
// Fediverse microblogging platform). A plain composable kurly.worker (a Deployment with no
// Service) on the same image as the web stage, with the Sidekiq entrypoint, sharing Mastodon's
// PostgreSQL, Redis and Secret. Import it and render with kurly.list:
//
//   local sidekiq = import 'github.com/metio/kurly/workloads/mastodon/sidekiq.libsonnet';
//   kurly.list(sidekiq())
//
// It reads the same PostgreSQL/Redis connection and secrets as the web stage from the shared
// Secret via envFrom.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './sidekiq.image', '\n');
function(
  name='mastodon-sidekiq',
  image=defaultImage,
  replicas=1,
  // The PostgreSQL and Redis it stores everything in; the passwords come from the
  // Secret.
  dbHost='mastodon-db-rw',
  dbPort=5432,
  dbName='mastodon',
  dbUser='mastodon',
  redisHost='mastodon-cache-headless',
  redisPort=6379,
  secretName='mastodon',
  env={},
  resources={ requests: { cpu: '250m', memory: '768Mi' }, limits: { memory: '1536Mi' } },
  labels={},
  annotations={},
)
  kurly.worker(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.command(['bundle', 'exec', 'sidekiq'])
  + kurly.envFromSecret(secretName)
  + kurly.env({
    RAILS_ENV: 'production',
    DB_HOST: dbHost,
    DB_PORT: std.toString(dbPort),
    DB_NAME: dbName,
    DB_USER: dbUser,
    REDIS_HOST: redisHost,
    REDIS_PORT: std.toString(redisPort),
  } + env)
  + kurly.runAs(991, gid=991, fsGroup=991)
  + kurly.scratch('/mastodon/tmp', '256Mi')
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
