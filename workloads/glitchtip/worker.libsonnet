// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// glitchtip-worker — the GlitchTip background worker (a Celery worker with the beat
// scheduler that processes the ingested events, sends notifications, and runs
// periodic cleanup). It runs the same image as the `server` stage, wired to the same
// database, Redis, and Secret, but with no Service and no exposed port. A GlitchTip
// deployment needs at least one. Import it alongside the server and render with
// kurly.list:
//
//   local worker = import 'github.com/metio/kurly/workloads/glitchtip/worker.libsonnet';
//   kurly.list(worker())
//
// Scale it horizontally with kurly.replicas — the workers coordinate through Redis.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='glitchtip-worker',
  image='docker.io/glitchtip/glitchtip:v6.2.2',
  redisHost='glitchtip-cache',
  // The same Secret the server uses (DATABASE_URL and SECRET_KEY).
  secretName='glitchtip-secrets',
  replicas=1,
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    REDIS_URL: 'redis://' + redisHost + ':6379/0',
  };

  kurly.worker(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.command(['./bin/run-celery-with-beat.sh'])
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
