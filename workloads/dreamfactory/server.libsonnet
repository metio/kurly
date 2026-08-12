// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// dreamfactory — generates a documented REST API over databases and services you
// already have, with roles, API keys and rate limits in front of it. A composable
// kurly.http workload on the project's own image: its own configuration and user
// accounts live in an external database, and the APIs it generates reach whatever
// it is pointed at. Import it and render with kurly.list:
//
//   local dreamfactory = import 'github.com/metio/kurly/workloads/dreamfactory/server.libsonnet';
//   kurly.list(dreamfactory(dbHost='dreamfactory-db', secretName='dreamfactory'))
//
// Serves the admin console and the generated APIs on :80 — compose an exposure
// onto it.
//
// THE ENTRYPOINT REWRITES THE APPLICATION TREE, SO THE HARDENING IS RELAXED
// DELIBERATELY. On every start it edits .env in place with sed, links an nginx
// site, rewrites php-fpm's pool configuration and may run `composer install` —
// all inside the image, as root, before nginx and php-fpm start and drop to
// www-data. That needs a root container, a writable root filesystem and the
// runtime's default capabilities; each is relaxed here rather than pretended
// away, and the catalogue reports the resulting posture.
//
// APP KEY: the image generates one on first start and keeps it in .env — which is
// INSIDE the container, so it is regenerated on every restart and every session
// and encrypted field from the previous one becomes unreadable. `secretName`
// carries APP_KEY for that reason; it is not optional in any deployment that
// keeps data.
//
// WHAT IT CAN REACH IS THE POINT AND THE RISK. DreamFactory's job is to open an
// API onto other systems, so an operator with admin access can point it at any
// address this pod can reach. A NetworkPolicy limiting egress to the databases it
// is meant to expose is worth composing on.
//
// One replica, recreated: the shipped configuration keeps sessions and cache on
// local disk, so a second pod would answer with a different view of both.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='dreamfactory',
  image=defaultImage,
  // mysql, pgsql or sqlsrv — the database holding DreamFactory's OWN
  // configuration, not the ones it exposes.
  dbDriver='mysql',
  dbHost=null,
  dbPort=null,
  database='dreamfactory',
  dbUser='dreamfactory',
  // A Secret carrying APP_KEY and DB_PASSWORD.
  secretName=null,
  // The hostname nginx answers for; the shipped default is dreamfactory.app.
  serverName=null,
  // Set when something in front terminates TLS, so Laravel builds https links.
  behindTlsProxy=true,
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env(
    { DB_DRIVER: dbDriver, DB_DATABASE: database, DB_USERNAME: dbUser }
    + (if dbHost != null then { DB_HOST: dbHost } else {})
    + (if dbPort != null then { DB_PORT: std.toString(dbPort) } else {})
    + (if serverName != null then { SERVERNAME: serverName } else {})
    + (if behindTlsProxy then { HTTPS_HEADER: 'on' } else {})
    + env
  )
  // See the header: the entrypoint edits the application tree in place and the
  // web stack binds :80 before dropping to www-data.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  + kurly.writableRootFilesystem()
  + (if secretName != null then kurly.envFromSecret(secretName) else {})
  // Both `composer install` on a cold image and the first admin request are slow,
  // so the startup budget is generous and the gate is a connection — the first
  // page served is a setup form rather than a health endpoint.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 60 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
