// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// activepieces — an Activepieces server (a self-hosted, open-source no-code automation
// / workflow builder, à la Zapier). A plain composable kurly.http workload on the
// official all-in-one image, backed by an external PostgreSQL and Redis. Import it,
// point it at its backends, and render with kurly.list:
//
//   local activepieces = import 'github.com/metio/kurly/workloads/activepieces/server.libsonnet';
//   kurly.list(activepieces(frontendUrl='https://flows.example.com'))
//
// Serves the web app and API on :80 — compose an exposure onto it.
//
// BACKENDS & SECRETS: the PostgreSQL and Redis connection settings are env, from
// the dbHost/database/dbUser/redisHost parameters (defaults pair with a
// cnpg-cluster named activepieces-db and a Redis). The Secret holds only the
// sensitive values — AP_POSTGRES_PASSWORD, AP_ENCRYPTION_KEY and AP_JWT_SECRET —
// pulled in via envFrom; kurly authors no Secret.
//
// Stateless: flow state lives in PostgreSQL and Redis, not on a volume, so this is a
// plain rolling Deployment.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='activepieces',
  image=defaultImage,
  replicas=2,
  // The public URL (Activepieces builds absolute links and webhook URLs from it,
  // and the server refuses to start without it). Defaults to a localhost URL so a
  // default render boots; point it at the real host for a real deployment.
  frontendUrl='http://localhost:80',
  // The PostgreSQL and Redis the server connects to. The non-secret connection
  // settings are env; the password lives in the Secret (AP_POSTGRES_PASSWORD),
  // pulled in via envFrom alongside AP_ENCRYPTION_KEY and AP_JWT_SECRET.
  dbHost='activepieces-db-rw',
  database='activepieces',
  dbUser='activepieces',
  redisHost='activepieces-cache-headless',
  // The Secret holding AP_POSTGRES_PASSWORD, AP_ENCRYPTION_KEY and AP_JWT_SECRET
  // (kurly mints none), via envFrom.
  secretName='activepieces',
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    AP_QUEUE_MODE: 'REDIS',
    AP_EXECUTION_MODE: 'UNSANDBOXED',
    AP_FRONTEND_URL: frontendUrl,
    AP_POSTGRES_HOST: dbHost,
    AP_POSTGRES_PORT: '5432',
    AP_POSTGRES_DATABASE: database,
    AP_POSTGRES_USERNAME: dbUser,
    AP_REDIS_HOST: redisHost,
    AP_REDIS_PORT: '6379',
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.scratch('/tmp', '256Mi')
  // It runs under pm2, which keeps its state in the node account's home and creates
  // it on start — so a read-only root filesystem stops it at
  // "EROFS: read-only file system, mkdir '/home/node/.pm2'". A scratch there costs
  // less than making the whole filesystem writable for one directory.
  + kurly.scratch('/home/node', '64Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
