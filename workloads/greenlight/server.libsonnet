// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// greenlight — a Greenlight 3 server (the official BigBlueButton front-end: a Rails
// app for scheduling and joining BBB rooms and meetings). A plain composable
// kurly.http workload on the official image, backed by an external PostgreSQL and
// Redis. It reaches an existing BigBlueButton server over the network — kurly does
// not run BBB itself. Import it, point it at its backends, and render with kurly.list:
//
//   local greenlight = import 'github.com/metio/kurly/workloads/greenlight/server.libsonnet';
//   kurly.list(greenlight())
//
// Serves the web app on :3000 — compose an exposure onto it.
//
// BACKENDS & SECRETS: Greenlight reads DATABASE_URL, REDIS_URL, SECRET_KEY_BASE and
// the BigBlueButton endpoint/secret (BIGBLUEBUTTON_ENDPOINT, BIGBLUEBUTTON_SECRET)
// from the environment. kurly authors no Secret; provide one holding them, pulled in
// via envFrom. The defaults pair with a cnpg-cluster named greenlight-db and a Redis.
//
// Stateless: uploaded recordings and presentations live on the BBB server, not here,
// so this is a plain rolling Deployment with no volume.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='greenlight',
  image='docker.io/bigbluebutton/greenlight:v3.8.2.3',
  replicas=2,
  // The Secret holding DATABASE_URL, REDIS_URL, SECRET_KEY_BASE and the
  // BIGBLUEBUTTON_* endpoint/secret (kurly mints none), via envFrom.
  secretName='greenlight-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.envFromSecret(secretName)
  + kurly.env({ RAILS_ENV: 'production' } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
