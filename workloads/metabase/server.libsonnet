// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// metabase — a Metabase server (an open-source business-intelligence and analytics
// tool). A plain composable kurly.http workload on the official image, backed by an
// external PostgreSQL for its application database. Import it, point it at a
// database, and render with kurly.list:
//
//   local metabase = import 'github.com/metio/kurly/workloads/metabase/server.libsonnet';
//   kurly.list(metabase())
//
// Serves the web app and API on :3000 — compose an exposure onto it. Its application
// state lives in the database, so this workload is stateless and can run several
// replicas.
//
// DATABASE & SECRETS: Metabase reads its application-database coordinates from env
// and MB_DB_PASS from the environment. The non-secret coordinates default to a
// cnpg-cluster named metabase-db; the password comes from a provided Secret via
// envFrom. kurly authors no Secret.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='metabase',
  image='docker.io/metabase/metabase:v0.62.5',
  dbHost='metabase-db-rw',
  dbName='metabase',
  dbUser='metabase',
  // The Secret holding MB_DB_PASS (kurly mints none), via envFrom.
  secretName='metabase-secrets',
  replicas=1,
  env={},
  resources={ requests: { cpu: '300m', memory: '1Gi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    MB_DB_TYPE: 'postgres',
    MB_DB_HOST: dbHost,
    MB_DB_PORT: '5432',
    MB_DB_DBNAME: dbName,
    MB_DB_USER: dbUser,
    MB_JETTY_PORT: '3000',
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.readinessProbe({ httpGet: { path: '/api/health', port: 'http' }, initialDelaySeconds: 30, periodSeconds: 15, failureThreshold: 20 })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' }, initialDelaySeconds: 60 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
