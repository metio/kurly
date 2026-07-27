// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// authentik (server) — an authentik server (a self-hosted identity provider and SSO: OAuth2,
// SAML, LDAP, forward-auth and more). authentik runs as TWO workloads — this web/API server and
// a companion `worker` (the background stage) — both on the same image, backed by an external
// PostgreSQL and Redis. Import it, point it at its backends, and render with kurly.list:
//
//   local server = import 'github.com/metio/kurly/workloads/authentik/server.libsonnet';
//   kurly.list(server())
//
// Serves the web app and API on :9000, with the HTTPS listener on :9443 published on the
// Service beside it (the 'https' port) — compose an exposure onto the HTTP port.
//
// BACKENDS & SECRETS: authentik reads its PostgreSQL and Redis connection (AUTHENTIK_POSTGRESQL__*
// and AUTHENTIK_REDIS__*) and AUTHENTIK_SECRET_KEY from the environment. kurly authors no Secret;
// provide one holding them, via envFrom. The server and worker share it. The defaults pair with a
// cnpg-cluster named authentik-db and a Redis.
//
// Stateless: state lives in PostgreSQL and Redis, so this is a plain rolling Deployment.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='authentik',
  image=defaultImage,
  replicas=2,
  // The PostgreSQL and Redis authentik connects to. Non-secret connection
  // settings are env; the DB password lives in the Secret alongside
  // AUTHENTIK_SECRET_KEY (envFrom).
  dbHost='authentik-db-rw',
  database='authentik',
  dbUser='authentik',
  redisHost='authentik-cache-headless',
  secretName='authentik',
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.args(['server'])
  + kurly.port(9000)
  + kurly.servicePort(9000)
  + kurly.extraPort('https', 9443)
  + kurly.envFromSecret(secretName)
  + kurly.env({
    AUTHENTIK_POSTGRESQL__HOST: dbHost,
    AUTHENTIK_POSTGRESQL__NAME: database,
    AUTHENTIK_POSTGRESQL__USER: dbUser,
    AUTHENTIK_REDIS__HOST: redisHost,
  } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.scratch('/tmp', '128Mi')
  + kurly.readinessProbe({ httpGet: { path: '/-/health/ready/', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/-/health/live/', port: 'http' } })
  // The server applies database migrations on first boot before it serves; a
  // startup probe holds liveness until it is up (~5min grace).
  + kurly.startupProbe({ httpGet: { path: '/-/health/live/', port: 'http' }, failureThreshold: 60, periodSeconds: 5 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
