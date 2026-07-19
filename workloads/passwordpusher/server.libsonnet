// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// passwordpusher — a Password Pusher server (share passwords and secrets over
// self-destructing, expiring links). A plain composable kurly.http workload on the
// official image, backed by an external PostgreSQL. Import it, point it at a
// database, and render with kurly.list:
//
//   local pwpush = import 'github.com/metio/kurly/workloads/passwordpusher/server.libsonnet';
//   kurly.list(pwpush())
//
// Serves the web UI and API on :5100 — compose an exposure onto it. Being stateless
// (its state lives in the database), it can run several replicas.
//
// DATABASE & SECRETS: Password Pusher reads DATABASE_URL and SECRET_KEY_BASE from
// the environment. kurly authors no Secret; provide one holding both keys (the
// database password is embedded in DATABASE_URL) and it is pulled in via envFrom.
// The defaults pair with a cnpg-cluster named passwordpusher-db.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='passwordpusher',
  image='docker.io/pglombardo/pwpush:v2.9.3',
  // The Secret holding DATABASE_URL and SECRET_KEY_BASE (kurly mints none),
  // pulled into the environment via envFrom.
  secretName='passwordpusher-secrets',
  replicas=1,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(5100)
  + kurly.servicePort(5100)
  + kurly.envFromSecret(secretName)
  + (if env == {} then {} else kurly.env(env))
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
