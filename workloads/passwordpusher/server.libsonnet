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
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='passwordpusher',
  image=defaultImage,
  // The Secret holding DATABASE_URL and SECRET_KEY_BASE (kurly mints none),
  // pulled into the environment via envFrom.
  secretName='passwordpusher',
  replicas=1,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  // The image's server listens on :80; the Service keeps the app's conventional
  // :5100 for consumers.
  + kurly.port(80)
  + kurly.servicePort(5100)
  + kurly.envFromSecret(secretName)
  + (if env == {} then {} else kurly.env(env))
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.scratch('/tmp', '64Mi')
  // Rails creates working directories under the app's own tmp/ as it boots — cache,
  // pids, sockets, rack_attack_cache — and naming them one at a time takes a boot
  // each to discover the next. The whole directory is the scratch instead.
  //
  // The one thing tmp/ ships is local_secret.txt, the secret Rails generates when
  // it has none. Hiding it is safe HERE because it is not the source of truth: this
  // stage reads SECRET_KEY_BASE from its Secret, which the catalogue declares. Were
  // that not so, a password-sharing app minting a fresh secret on every restart
  // could not read back anything it had encrypted — so this is a fact about the
  // stage's configuration, not a general licence to scratch a Rails tmp/.
  + kurly.scratch('/opt/PasswordPusher/tmp', '128Mi')
  // Rails migrates and warms its caches before it listens.
  // Rails compiles its bootsnap cache and runs its queue inside the app directory.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 45 })
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
