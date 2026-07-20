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
// Serves the web app and API on :9000 — compose an exposure onto it.
//
// BACKENDS & SECRETS: authentik reads its PostgreSQL and Redis connection (AUTHENTIK_POSTGRESQL__*
// and AUTHENTIK_REDIS__*) and AUTHENTIK_SECRET_KEY from the environment. kurly authors no Secret;
// provide one holding them, via envFrom. The server and worker share it. The defaults pair with a
// cnpg-cluster named authentik-db and a Redis.
//
// Stateless: state lives in PostgreSQL and Redis, so this is a plain rolling Deployment.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='authentik',
  image='ghcr.io/goauthentik/server:2024.10.5',
  replicas=2,
  secretName='authentik-secrets',
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.command(['server'])
  + kurly.port(9000)
  + kurly.servicePort(9000)
  + kurly.envFromSecret(secretName)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.scratch('/tmp', '128Mi')
  + kurly.readinessProbe({ httpGet: { path: '/-/health/ready/', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/-/health/live/', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
