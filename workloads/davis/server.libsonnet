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
function(
  name='davis',
  image='ghcr.io/tchapi/davis:latest@sha256:60195a4f241f75957cfb5a0d371cb5b2898102153b0447f5a9ec13860eb49320',
  replicas=2,
  secretName='davis-secrets',
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.envFromSecret(secretName)
  + kurly.env(env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
