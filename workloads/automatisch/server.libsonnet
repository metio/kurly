// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// automatisch (server) — an Automatisch web server (a self-hosted, open-source
// business-automation / workflow tool, an open alternative to Zapier). A plain
// composable kurly.http workload on the official image, backed by an external
// PostgreSQL and Redis. Background flow execution runs in the companion `worker` stage.
// Import it, point it at its backends, and render with kurly.list:
//
//   local server = import 'github.com/metio/kurly/workloads/automatisch/server.libsonnet';
//   kurly.list(server())
//
// Serves the web app and API on :3000 — compose an exposure onto it.
//
// BACKENDS & SECRETS: Automatisch reads its PostgreSQL and Redis connection, plus
// ENCRYPTION_KEY, WEBHOOK_SECRET_KEY and APP_SECRET_KEY, from the environment. kurly
// authors no Secret; provide one holding them, pulled in via envFrom. The defaults pair
// with a cnpg-cluster named automatisch-db and a Redis. The server and worker share the
// same Secret.
//
// Stateless: flow state lives in PostgreSQL and Redis, so this is a plain rolling
// Deployment.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='automatisch',
  image='ghcr.io/automatisch/automatisch:0.15.0',
  replicas=2,
  // The Secret holding the PostgreSQL/Redis connection and the ENCRYPTION_KEY /
  // WEBHOOK_SECRET_KEY / APP_SECRET_KEY (kurly mints none), via envFrom.
  secretName='automatisch-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.envFromSecret(secretName)
  + kurly.env({ APP_ENV: 'production', PORT: '3000' } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.scratch('/tmp', '128Mi')
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
