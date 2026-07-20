// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// joplin — a Joplin Server (the self-hosted sync target for the Joplin note-taking apps:
// your notes and notebooks sync through it across devices, end-to-end encrypted). A plain
// composable kurly.http workload on the official image, backed by an external PostgreSQL.
// Import it, point it at a database, and render with kurly.list:
//
//   local joplin = import 'github.com/metio/kurly/workloads/joplin/server.libsonnet';
//   kurly.list(joplin(appBaseUrl='https://joplin.example.com'))
//
// Serves the sync API on :22300 — compose an exposure onto it.
//
// DATABASE & SECRETS: Joplin Server reads its PostgreSQL connection (POSTGRES_*) from the
// environment. kurly authors no Secret; provide one holding them, pulled in via envFrom.
// The defaults pair with a cnpg-cluster named joplin-db.
//
// Stateless: notes live in PostgreSQL, so this is a plain rolling Deployment.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='joplin',
  image='docker.io/joplin/server:3.4.2',
  replicas=2,
  appBaseUrl=null,
  secretName='joplin-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv =
    { APP_PORT: '22300', DB_CLIENT: 'pg' }
    + (if appBaseUrl == null then {} else { APP_BASE_URL: appBaseUrl });
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(22300)
  + kurly.servicePort(22300)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ httpGet: { path: '/api/ping', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/ping', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
