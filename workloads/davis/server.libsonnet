// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// davis — a Davis server (a self-hosted CalDAV and CardDAV server with a simple admin UI, built on
// sabre/dav — a lightweight way to host your own calendars and contacts). A plain composable
// kurly.http workload on the official image, backed by an external database (MySQL/MariaDB,
// PostgreSQL, or SQLite). Import it, point it at its backend, and render with kurly.list:
//
//   local davis = import 'github.com/metio/kurly/workloads/davis/server.libsonnet';
//   kurly.list(davis())
//
// Serves the web UI and the CalDAV/CardDAV endpoints on :80 — compose an exposure onto it.
//
// BACKENDS & SECRETS: Davis reads DATABASE_URL, APP_SECRET and the admin login from the
// environment. kurly authors no Secret; provide one holding them, via envFrom. Pair it with a
// database you run separately (e.g. a cnpg-cluster named davis-db for PostgreSQL).
//
// Stateless: calendars and contacts live in the database, so a plain rolling Deployment.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');
function(
  name='davis',
  image=defaultImage,
  replicas=2,
  secretName='davis',
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  // The bundled Caddy serves the app on :9000; the Service keeps :80.
  + kurly.port(9000)
  + kurly.servicePort(80)
  + kurly.envFromSecret(secretName)
  + kurly.env(env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  // php-fpm starts as root and drops its worker pool to the web user, so it keeps
  // the SETUID/SETGID capabilities; without them it exits on a config error.
  + kurly.keepCapabilities()
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
