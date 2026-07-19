// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// maybe — a Maybe server (a self-hosted personal finance and net-worth manager). A
// plain composable kurly.http workload backed by an external PostgreSQL and Redis,
// with its Active Storage uploads on a PersistentVolume. Import it, point it at a
// database and cache, and render with kurly.list:
//
//   local maybe = import 'github.com/metio/kurly/workloads/maybe/server.libsonnet';
//   kurly.list(maybe())
//
// Serves the web app on :3000 — compose an exposure onto it.
//
// DATABASE, CACHE & SECRETS: Maybe reads its database and Redis coordinates and its
// SECRET_KEY_BASE from the environment. The non-secret coordinates default to a
// cnpg-cluster named maybe-db and a valkey named maybe-cache; the sensitive values
// (POSTGRES_PASSWORD, SECRET_KEY_BASE) come from a provided Secret via envFrom.
// kurly authors no Secret.
//
// The Rails app writes to several paths under /rails at runtime, so this relaxes
// the read-only-rootfs default while keeping non-root, dropped capabilities, and no
// privilege escalation.
//
// Single writer: Active Storage uploads live on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the files. A separate
// Sidekiq worker (background jobs) can be added as a second deployment.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='maybe',
  image='ghcr.io/maybe-finance/maybe:0.1.0-alpha.6',
  storageSize='2Gi',
  storageClass=null,
  dbHost='maybe-db-rw',
  dbName='maybe',
  dbUser='maybe',
  redisHost='maybe-cache',
  // The Secret holding POSTGRES_PASSWORD and SECRET_KEY_BASE (kurly mints none),
  // via envFrom.
  secretName='maybe-secrets',
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    SELF_HOSTED: 'true',
    RAILS_ENV: 'production',
    RAILS_FORCE_SSL: 'false',
    RAILS_ASSUME_SSL: 'false',
    DB_HOST: dbHost,
    DB_PORT: '5432',
    POSTGRES_DB: dbName,
    POSTGRES_USER: dbUser,
    REDIS_URL: 'redis://' + redisHost + ':6379/1',
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/rails/storage', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/up', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/up', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
