// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// postal-worker — the Postal background worker (the process that actually
// delivers the queued mail, retries what bounced, expires held messages and fires
// the outgoing webhooks). It runs the same official image as the `server` stage,
// wired to the same databases and the same Secret, with no Service and no port. A
// Postal install without one queues mail and sends none. Import it alongside the
// server and render with kurly.list:
//
//   local worker = import 'github.com/metio/kurly/workloads/postal/worker.libsonnet';
//   kurly.list(worker())
//
// Deploy it after `server`, which creates the schema both read.
//
// Scale it horizontally with kurly.replicas — the workers claim queued messages
// through the shared database, so several run side by side without conflict.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './worker.image', '\n');

function(
  name='postal-worker',
  image=defaultImage,
  webHostname='postal.example.com',
  webProtocol='https',
  smtpHostname='postal.example.com',
  dbHost='postal-db',
  dbPort=3306,
  database='postal',
  dbUser='postal',
  messageDbUser='postal',
  messageDbPrefix='postal',
  // The same Secret the server reads, holding MAIN_DB_PASSWORD,
  // MESSAGE_DB_PASSWORD, RAILS_SECRET_KEY and SIGNING_KEY.
  secretName='postal',
  replicas=1,
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.worker(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.args(['postal', 'worker'])
  + kurly.env(
    {
      MAIN_DB_HOST: dbHost,
      MAIN_DB_PORT: std.toString(dbPort),
      MAIN_DB_USERNAME: dbUser,
      MAIN_DB_DATABASE: database,
      MESSAGE_DB_HOST: dbHost,
      MESSAGE_DB_PORT: std.toString(dbPort),
      MESSAGE_DB_USERNAME: messageDbUser,
      MESSAGE_DB_DATABASE_NAME_PREFIX: messageDbPrefix,
      POSTAL_WEB_HOSTNAME: webHostname,
      POSTAL_WEB_PROTOCOL: webProtocol,
      POSTAL_SMTP_HOSTNAME: smtpHostname,
      // The worker signs what it delivers, so it reads the same key file the
      // server does.
      POSTAL_SIGNING_KEY_PATH: '/secrets/SIGNING_KEY',
      WAIT_FOR_TARGETS: dbHost + ':' + std.toString(dbPort),
      WAIT_FOR_TIMEOUT: '120',
    } + env
  )
  + kurly.envFromSecret(secretName)
  + kurly.secretMount(secretName, '/secrets')
  + kurly.runAs(999, gid=999, fsGroup=999)
  + kurly.scratch('/opt/postal/app/tmp', '256Mi')
  + kurly.scratch('/opt/postal/app/log', '128Mi')
  + kurly.scratch('/tmp', '128Mi')
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
