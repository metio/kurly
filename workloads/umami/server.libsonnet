// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// umami — an Umami server (a simple, privacy-focused, self-hosted web-analytics
// alternative to Google Analytics). A plain composable kurly.http workload on the
// official image, backed by an external PostgreSQL. Import it, point it at a
// database, and render with kurly.list:
//
//   local umami = import 'github.com/metio/kurly/workloads/umami/server.libsonnet';
//   kurly.list(umami())
//
// Serves the dashboard and tracking API on :3000 — compose an exposure onto it.
// Being stateless (its state lives in the database), it can run several replicas.
//
// DATABASE & SECRETS: Umami reads DATABASE_URL (with the database password embedded)
// and APP_SECRET from the environment. kurly authors no Secret; provide one holding
// both, pulled in via envFrom. The defaults pair with a cnpg-cluster named umami-db.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='umami',
  image='ghcr.io/umami-software/umami:postgresql-v2.15.1',
  // The Secret holding DATABASE_URL and APP_SECRET (kurly mints none), via envFrom.
  secretName='umami-secrets',
  replicas=1,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.envFromSecret(secretName)
  + kurly.env({ DATABASE_TYPE: 'postgresql' } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ httpGet: { path: '/api/heartbeat', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/heartbeat', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
