// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// seatsurfing — a Seatsurfing server (desk and meeting-room booking / hot-desking).
// A plain composable kurly.http workload on the official image, backed by an
// external PostgreSQL. Import it, point it at a database, and render with
// kurly.list:
//
//   local seatsurfing = import 'github.com/metio/kurly/workloads/seatsurfing/server.libsonnet';
//   kurly.list(seatsurfing(env={ PUBLIC_URL: 'https://booking.example.com' }))
//
// Serves the web UI and API on :8080 — compose an exposure onto it. Being stateless
// (its state lives in the database), it can run several replicas.
//
// DATABASE & SECRETS: Seatsurfing reads POSTGRES_URL and JWT_SIGNING_KEY from the
// environment. kurly authors no Secret; provide one holding both (the database
// password is embedded in POSTGRES_URL), pulled in via envFrom. The defaults pair
// with a cnpg-cluster named seatsurfing-db.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='seatsurfing',
  image='ghcr.io/seatsurfing/seatsurfing:1.116.0',
  // The Secret holding POSTGRES_URL and JWT_SIGNING_KEY (kurly mints none),
  // pulled into the environment via envFrom.
  secretName='seatsurfing-secrets',
  replicas=1,
  // Non-sensitive settings (PUBLIC_URL, FRONTEND_URL, …).
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.envFromSecret(secretName)
  + (if env == {} then {} else kurly.env(env))
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.scratch('/tmp', '32Mi')
  + kurly.readinessProbe({ httpGet: { path: '/healthz', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/healthz', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
