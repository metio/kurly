// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// rocketchat — a Rocket.Chat server (a self-hosted, open-source team chat and
// collaboration platform). A plain composable kurly.http workload on the official
// image, backed by an external MongoDB replica set (Rocket.Chat requires the oplog).
// Import it, point it at MongoDB, and render with kurly.list:
//
//   local rocketchat = import 'github.com/metio/kurly/workloads/rocketchat/server.libsonnet';
//   kurly.list(rocketchat(rootUrl='https://chat.example.com'))
//
// Serves the web app and API on :3000 — compose an exposure onto it.
//
// DATABASE & SECRETS: Rocket.Chat reads MONGO_URL and MONGO_OPLOG_URL from the
// environment (the oplog URL drives its real-time updates, so MongoDB MUST be a replica
// set). kurly authors no Secret; provide one holding both, pulled in via envFrom. Pairs
// with a mongodb-cluster named rocketchat-db.
//
// Stateless: uploaded files live in MongoDB (GridFS) by default, not on a volume, so
// this is a plain rolling Deployment that scales freely.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='rocketchat',
  image='docker.io/rocketchat/rocket.chat:8.6.1',
  replicas=2,
  // The public URL (Rocket.Chat builds absolute links and validates it).
  rootUrl=null,
  // The Secret holding MONGO_URL and MONGO_OPLOG_URL (kurly mints none), via envFrom.
  secretName='rocketchat-secrets',
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv =
    { PORT: '3000', DEPLOY_METHOD: 'kubernetes' }
    + (if rootUrl == null then {} else { ROOT_URL: rootUrl });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.scratch('/tmp', '128Mi')
  + kurly.readinessProbe({ httpGet: { path: '/api/info', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/info', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
