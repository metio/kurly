// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// traduora — an ever-traduora server (a translation management platform: teams
// edit their locales in a web UI, and an import/export API moves the same
// strings in and out of a build). A composable kurly.http workload backed by an
// EXTERNAL PostgreSQL — the cnpg-cluster workload provides one — and holding no
// state of its own. Import it and render
// with kurly.list:
//
//   local traduora = import 'github.com/metio/kurly/workloads/traduora/server.libsonnet';
//   kurly.list(traduora())
//
// Serves the web app and the API on :8080 — compose an exposure onto it.
//
// Stateless: everything lives in the database, so this is a plain rolling
// Deployment.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='traduora',
  image=defaultImage,
  // The database it connects to. `dbType` is traduora's own vocabulary:
  // 'postgres' or 'mysql'. The credentials live in the Secret. PostgreSQL is the
  // default because traduora's own migrations do not apply cleanly on MariaDB
  // (an early one alters a column another table's foreign key depends on).
  dbType='postgres',
  dbHost='traduora-db-rw',
  dbPort=5432,
  database='traduora',
  // The URL users reach this instance on. It goes into the mails traduora
  // sends, so a wrong value produces invitation links nobody can follow.
  virtualHost='http://localhost:8080',
  // The Secret holding TR_DB_USER, TR_DB_PASSWORD and TR_SECRET. TR_SECRET
  // signs every access token and ships with the published default `secret`,
  // so supplying it is the difference between having accounts and not.
  secretName='traduora',
  signupsEnabled=true,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env(
    {
      TR_PORT: '8080',
      TR_DB_TYPE: dbType,
      TR_DB_HOST: dbHost,
      TR_DB_PORT: std.toString(dbPort),
      TR_DB_DATABASE: database,
      TR_DB_AUTOMIGRATE: 'true',
      TR_VIRTUAL_HOST: virtualHost,
      TR_SIGNUPS_ENABLED: if signupsEnabled then 'true' else 'false',
      NODE_ENV: 'production',
    } + env
  )
  + kurly.envFromSecret(secretName)
  // The image sets no USER, so the hardened default (runAsNonRoot with no uid)
  // would be refused by the kubelet. node:alpine ships the `node` account at
  // 1000, and nothing in the tree is written at runtime.
  + kurly.runAs(1000, 1000)
  // node writes its temporary files here, and the root filesystem stays
  // read-only.
  + kurly.scratch('/tmp')
  // The first start migrates the schema before the server listens.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
