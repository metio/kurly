// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// etherpad — an Etherpad server (a real-time collaborative document editor). A plain
// composable kurly.http workload on the official image, backed by an external
// PostgreSQL. Import it, point it at a database, and render with kurly.list:
//
//   local etherpad = import 'github.com/metio/kurly/workloads/etherpad/server.libsonnet';
//   kurly.list(etherpad())
//
// Serves the editor and API on :9001 — compose an exposure onto it.
//
// DATABASE & SECRETS: Etherpad reads its database coordinates and DB_PASS, plus
// ADMIN_PASSWORD and APIKEY, from the environment. The non-secret coordinates default
// to a cnpg-cluster named etherpad-db; the secrets come from a provided Secret via
// envFrom. kurly authors no Secret.
//
// Its documents live in the database (not on disk), so this workload is stateless and
// can run several replicas.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='etherpad',
  image='docker.io/etherpad/etherpad:3.3.2',
  dbHost='etherpad-db-rw',
  dbName='etherpad',
  dbUser='etherpad',
  // The Secret holding DB_PASS, ADMIN_PASSWORD, and APIKEY (kurly mints none), via
  // envFrom.
  secretName='etherpad-secrets',
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
    ADMIN_USERNAME: 'admin',
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(9001)
  + kurly.servicePort(9001)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
