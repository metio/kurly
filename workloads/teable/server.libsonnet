// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// teable — a Teable server (a self-hosted, no-code database built on PostgreSQL that presents as a
// spreadsheet — an Airtable alternative). A plain composable kurly.http workload on the official
// image, backed by an external PostgreSQL (and Redis for realtime/caching). Import it, point it at
// its backends, and render with kurly.list:
//
//   local teable = import 'github.com/metio/kurly/workloads/teable/server.libsonnet';
//   kurly.list(teable(publicOrigin='https://teable.example.com'))
//
// Serves the web app on :3000 — compose an exposure onto it.
//
// BACKENDS & SECRETS: Teable reads PRISMA_DATABASE_URL, BACKEND_CACHE_REDIS_URI, SECRET_KEY and
// its mail/storage settings from the environment. kurly authors no Secret; provide one holding
// them, via envFrom. The defaults pair with a cnpg-cluster named teable-db and a Redis. Uploaded
// attachments go to S3 when the storage settings point at a bucket (otherwise local disk — add a
// store then).
//
// Stateless with S3 storage: a plain rolling Deployment.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='teable',
  image='ghcr.io/teableio/teable:latest@sha256:3d76dae237327e0d54dcc1aa073209088deb6d9bc4b6215a09462b3d133d4e19',
  replicas=2,
  publicOrigin=null,
  secretName='teable-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = if publicOrigin == null then {} else { PUBLIC_ORIGIN: publicOrigin };
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
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
