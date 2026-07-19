// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// twenty-worker — the Twenty background worker (BullMQ jobs: emails, imports,
// webhooks, scheduled tasks). It runs the same image as the `server` stage, wired
// to the same database, Redis, and Secret, but with no Service and no exposed port.
// A Twenty deployment needs at least one. Import it alongside the server and render
// with kurly.list:
//
//   local worker = import 'github.com/metio/kurly/workloads/twenty/worker.libsonnet';
//   kurly.list(worker())
//
// Scale it horizontally with kurly.replicas — the workers coordinate through Redis.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='twenty-worker',
  image='docker.io/twentycrm/twenty:v2.22.0',
  redisHost='twenty-cache',
  // The same Secret the server uses (PG_DATABASE_URL and APP_SECRET).
  secretName='twenty-secrets',
  replicas=1,
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    REDIS_URL: 'redis://' + redisHost + ':6379',
    STORAGE_TYPE: 'local',
    STORAGE_LOCAL_PATH: '.local-storage',
  };

  kurly.worker(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.command(['yarn', 'worker:prod'])
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
