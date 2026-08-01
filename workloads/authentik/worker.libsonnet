// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// authentik (worker) — the authentik background worker: it runs migrations, scheduled tasks,
// outpost management and the flows the server enqueues. A plain composable kurly.worker (a
// Deployment with no Service) on the same image as the server, with the worker entrypoint,
// sharing the server's PostgreSQL, Redis and Secret. Import it and render with kurly.list:
//
//   local worker = import 'github.com/metio/kurly/workloads/authentik/worker.libsonnet';
//   kurly.list(worker())
//
// BACKENDS & SECRETS: same as the server — the PostgreSQL/Redis connection and AUTHENTIK_SECRET_KEY
// come from the shared Secret via envFrom.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './worker.image', '\n');

function(
  name='authentik-worker',
  image=defaultImage,
  replicas=1,
  dbHost='authentik-db-rw',
  database='authentik',
  dbUser='authentik',
  redisHost='authentik-cache-headless',
  secretName='authentik',
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.worker(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.args(['worker'])
  + kurly.envFromSecret(secretName)
  + kurly.env({
    AUTHENTIK_POSTGRESQL__HOST: dbHost,
    AUTHENTIK_POSTGRESQL__NAME: database,
    AUTHENTIK_POSTGRESQL__USER: dbUser,
    AUTHENTIK_REDIS__HOST: redisHost,
  } + env)
  // Kept: authentik cannot boot on this host at all — two replicas race its
  // first-boot migration on a lock and the second overruns its startup probe —
  // so a read-only root filesystem here would be an untested claim. Remove it
  // when the migration ordering is solved and the workload can be booted to
  // prove it.
  + kurly.writableRootFilesystem()
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.scratch('/tmp', '128Mi')
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
