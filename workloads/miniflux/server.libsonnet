// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// miniflux — a Miniflux server (a minimalist, opinionated RSS/Atom feed reader). A
// plain composable kurly.http workload on the official image, backed by an external
// PostgreSQL. Import it, point it at a database, and render with kurly.list:
//
//   local miniflux = import 'github.com/metio/kurly/workloads/miniflux/server.libsonnet';
//   kurly.list(miniflux())
//
// Serves the web app and API on :8080 — compose an exposure onto it. Being stateless
// (its state lives in the database), it can run several replicas.
//
// DATABASE & SECRETS: Miniflux reads DATABASE_URL (with the database password
// embedded) and the first-run admin password from the environment. kurly authors no
// Secret; provide one holding DATABASE_URL and ADMIN_PASSWORD, pulled in via envFrom.
// The defaults pair with a cnpg-cluster named miniflux-db.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='miniflux',
  image='docker.io/miniflux/miniflux:2.3.2',
  // The Secret holding DATABASE_URL and ADMIN_PASSWORD (kurly mints none), via
  // envFrom.
  secretName='miniflux-secrets',
  // Create the admin account on first start (its password comes from the Secret).
  adminUser='admin',
  replicas=1,
  env={},
  resources={ requests: { cpu: '25m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.envFromSecret(secretName)
  + kurly.env({
    RUN_MIGRATIONS: '1',
    CREATE_ADMIN: '1',
    ADMIN_USERNAME: adminUser,
    LISTEN_ADDR: '0.0.0.0:8080',
  } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.readinessProbe({ httpGet: { path: '/healthcheck', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/healthcheck', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
