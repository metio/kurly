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
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='rocketchat',
  image=defaultImage,
  replicas=2,
  // The public URL (Rocket.Chat builds absolute links and validates it).
  rootUrl=null,
  // The Secret holding MONGO_URL and MONGO_OPLOG_URL (kurly mints none), via envFrom.
  secretName='rocketchat',
  env={},
  // 2Gi, because 1Gi does not start. Rocket.Chat is a Meteor application and
  // its Node process is past a gigabyte before it finishes loading, so the
  // container is OOM-killed during startup — exit 137, no log line, and a pod
  // that reads as crash-looping for reasons of its own.
  resources={ requests: { cpu: '250m', memory: '1Gi' }, limits: { memory: '2Gi' } },
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
  + kurly.scratch('/tmp', '128Mi')
  // Kept as UNVERIFIABLE rather than needed: Rocket.Chat is MongoDB-only and
  // MongoDB does not start on this host's kernel, so nothing here can boot it to
  // show a read-only root filesystem works. Its attempt produced no read-only
  // error, so this likely comes off — on a host that can run MongoDB.
  + kurly.writableRootFilesystem()
  + kurly.readinessProbe({ httpGet: { path: '/api/info', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/info', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
