// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// redash-scheduler — the Redash RQ scheduler: it enqueues the periodic work, so
// this is what makes a query with a refresh interval actually refresh and a
// schema get re-read. Same image, database, Redis and Secret as the `server`
// stage, with no Service and no port. Import it alongside the server and a worker
// and render with kurly.list:
//
//   local scheduler = import 'github.com/metio/kurly/workloads/redash/scheduler.libsonnet';
//   kurly.list(scheduler())
//
// EXACTLY ONE REPLICA, and no way to ask for more: every instance would enqueue
// the same periodic jobs, so a second one doubles the load on the data sources
// while changing nothing a user sees. The schedule lives in Redis, so this claims
// no volume and a restarted pod picks up where the last one left off.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './scheduler.image', '\n');

function(
  name='redash-scheduler',
  image=defaultImage,
  // The same Secret the server reads, holding REDASH_DATABASE_URL,
  // REDASH_REDIS_URL, REDASH_SECRET_KEY and REDASH_COOKIE_SECRET.
  secretName='redash',
  // Extra environment, merged over the below.
  env={},
  resources={ requests: { cpu: '50m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.worker(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.args(['scheduler'])
  + kurly.envFromSecret(secretName)
  + kurly.env(
    {
      PYTHONUNBUFFERED: '0',
      REDASH_LOG_LEVEL: 'INFO',
    } + env
  )
  + kurly.disableServiceLinks()
  // Same uid as the server, so both read the shared Secret identically.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.scratch('/tmp', '128Mi')
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
