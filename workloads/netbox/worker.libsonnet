// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// netbox-worker — the NetBox background task worker (an RQ worker draining the
// high/default/low queues). It runs the same community image as the `server`
// stage, wired to the same database, Redis, and Secret, but with no Service and no
// exposed port: it processes webhooks, report/script runs, and housekeeping jobs
// the web front end enqueues. A NetBox deployment needs at least one. Import it
// alongside the server and render with kurly.list:
//
//   local worker = import 'github.com/metio/kurly/workloads/netbox/worker.libsonnet';
//   kurly.list(worker())
//
// Scale it horizontally with kurly.replicas — the workers coordinate through the
// shared Redis queue, so several run side by side without conflict. It mounts no
// media volume by default; reports or scripts that write to media need shared
// (RWX) storage composed on with kurly.store.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// The workload version, stamped as app.kubernetes.io/version; the release
// pipeline overwrites version.txt with the calver.
local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='netbox-worker',
  image='docker.io/netboxcommunity/netbox:v4.6.5',
  dbHost='netbox-db-rw',
  dbName='netbox',
  dbUser='netbox',
  redisHost='netbox-cache',
  // The same Secret the server mounts, holding secret_key and db_password.
  secretName='netbox-secrets',
  replicas=1,
  // Extra environment, merged over the below.
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    DB_HOST: dbHost,
    DB_NAME: dbName,
    DB_USER: dbUser,
    DB_PORT: '5432',
    REDIS_HOST: redisHost,
    REDIS_PORT: '6379',
    REDIS_DATABASE: '0',
    REDIS_CACHE_HOST: redisHost,
    REDIS_CACHE_PORT: '6379',
    REDIS_CACHE_DATABASE: '1',
  };

  kurly.worker(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.command(['/opt/netbox/venv/bin/python', '/opt/netbox/netbox/manage.py', 'rqworker', 'high', 'default', 'low'])
  + kurly.env(baseEnv + env)
  // Same non-root uid as the server so both read the shared Secret identically.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.scratch('/tmp', '128Mi')
  + kurly.secretMount(secretName, '/run/secrets')
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
