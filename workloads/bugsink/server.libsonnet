// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// bugsink — a Bugsink server (a self-hosted, Sentry-compatible error tracker: it
// ingests the same events your existing Sentry SDKs already emit). A plain composable
// kurly.http workload on the official image, backed by an external PostgreSQL or
// MySQL. Import it, point it at a database, and render with kurly.list:
//
//   local bugsink = import 'github.com/metio/kurly/workloads/bugsink/server.libsonnet';
//   kurly.list(bugsink(baseUrl='https://errors.example.com'))
//
// Serves the web app and the event-ingestion API on :8000 — compose an exposure onto it.
//
// DATABASE & SECRETS: Bugsink reads DATABASE_URL and SECRET_KEY from the environment.
// kurly authors no Secret; provide one holding both, pulled in via envFrom. The
// defaults pair with a cnpg-cluster named bugsink-db.
//
// Stateless when backed by an external database (events live in the DB), so this is a
// plain rolling Deployment with no volume.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='bugsink',
  image='docker.io/bugsink/bugsink:2.4.0',
  replicas=2,
  // The public URL (Bugsink builds absolute links and validates the Host header).
  baseUrl=null,
  behindHttps=true,
  // The Secret holding DATABASE_URL and SECRET_KEY (kurly mints none), via envFrom.
  secretName='bugsink-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv =
    (if baseUrl == null then {} else { BASE_URL: baseUrl })
    + (if behindHttps then { BEHIND_HTTPS: 'true' } else {});

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8000)
  + kurly.servicePort(8000)
  + kurly.envFromSecret(secretName)
  + kurly.env({ PORT: '8000' } + baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
