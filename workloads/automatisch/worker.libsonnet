// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// automatisch (worker) — the Automatisch background worker: it runs the flow executions
// the web server enqueues onto Redis. A plain composable kurly.worker (a Deployment with
// no Service) on the same image as the server, with the worker entrypoint. It shares the
// server's PostgreSQL, Redis and Secret. Import it and render with kurly.list:
//
//   local worker = import 'github.com/metio/kurly/workloads/automatisch/worker.libsonnet';
//   kurly.list(worker())
//
// BACKENDS & SECRETS: same as the server — the worker reads the PostgreSQL and Redis
// connection and the ENCRYPTION_KEY / WEBHOOK_SECRET_KEY / APP_SECRET_KEY from the
// environment, via envFrom of the shared Secret.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './worker.image', '\n');

function(
  name='automatisch-worker',
  image=defaultImage,
  replicas=1,
  dbHost='automatisch-db-rw',
  database='automatisch',
  dbUser='automatisch',
  redisHost='automatisch-cache-headless',
  // The same Secret the server uses (the keys and the DB password).
  secretName='automatisch',
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.worker(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.command(['yarn', 'start:worker'])
  + kurly.envFromSecret(secretName)
  + kurly.env({
    APP_ENV: 'production',
    WORKER: 'true',
    POSTGRES_HOST: dbHost,
    POSTGRES_PORT: '5432',
    POSTGRES_DATABASE: database,
    POSTGRES_USERNAME: dbUser,
    REDIS_HOST: redisHost,
  } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.scratch('/tmp', '128Mi')
  // The app writes logs to its working directory, which uid 1000 cannot create
  // in the read-only image tree; give it a writable scratch there.
  + kurly.scratch('/automatisch/packages/backend/logs', '128Mi')
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
