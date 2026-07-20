// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// wikijs — a Wiki.js server (a modern, open-source wiki). A plain composable
// kurly.http workload on the official image, backed by an external PostgreSQL — its
// content and configuration live in the database, so the workload is stateless and
// can run several replicas. Import it, point it at a database, and render with
// kurly.list:
//
//   local wikijs = import 'github.com/metio/kurly/workloads/wikijs/server.libsonnet';
//   kurly.list(wikijs())
//
// Serves the wiki and API on :3000 — compose an exposure onto it.
//
// DATABASE & SECRETS: Wiki.js reads its database coordinates from env and DB_PASS
// from the environment. The non-secret coordinates default to a cnpg-cluster named
// wikijs-db; the password comes from a provided Secret via envFrom. kurly authors no
// Secret.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='wikijs',
  image='ghcr.io/requarks/wiki:2.5.314',
  dbHost='wikijs-db-rw',
  dbName='wikijs',
  dbUser='wikijs',
  // The Secret holding DB_PASS (kurly mints none), via envFrom.
  secretName='wikijs-secrets',
  replicas=1,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    DB_TYPE: 'postgres',
    DB_HOST: dbHost,
    DB_PORT: '5432',
    DB_NAME: dbName,
    DB_USER: dbUser,
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ httpGet: { path: '/healthz', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/healthz', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
