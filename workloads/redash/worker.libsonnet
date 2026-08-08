// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// redash-worker — the Redash RQ worker: it is what actually runs a query against
// a data source, refreshes a schema and sends a mail. The web server only
// enqueues, so a deployment without at least one worker accepts queries and never
// answers them. Same image, same database, same Redis and same Secret as the
// `server` stage, with no Service and no port. Import it alongside the server and
// render with kurly.list:
//
//   local worker = import 'github.com/metio/kurly/workloads/redash/worker.libsonnet';
//   kurly.list(worker())
//
// Scales horizontally with kurly.replicas — the workers coordinate through the
// shared Redis queues. `queues` picks which queues this deployment drains, so a
// second worker stage with `queues='queries'` and a bigger resource tier keeps ad
// hoc queries off the same pods as the scheduled ones.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './worker.image', '\n');

function(
  name='redash-worker',
  image=defaultImage,
  // The same Secret the server reads, holding REDASH_DATABASE_URL,
  // REDASH_REDIS_URL, REDASH_SECRET_KEY and REDASH_COOKIE_SECRET.
  secretName='redash',
  // The RQ queues this deployment drains, comma separated.
  queues='queries,scheduled_queries,schemas,default,periodic',
  // Worker processes inside one pod. Each one runs a query, so memory scales with
  // it and with the size of the results the data sources return.
  workersCount='2',
  replicas=1,
  // Extra environment, merged over the below.
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.worker(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.args(['worker'])
  + kurly.envFromSecret(secretName)
  + kurly.env(
    {
      PYTHONUNBUFFERED: '0',
      REDASH_LOG_LEVEL: 'INFO',
      QUEUES: queues,
      WORKERS_COUNT: workersCount,
    } + env
  )
  + kurly.disableServiceLinks()
  // Same uid as the server, so both read the shared Secret identically.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.scratch('/tmp', '256Mi')
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
