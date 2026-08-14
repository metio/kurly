// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// defguard/core — the identity and access half of defguard: user accounts, MFA,
// OpenID Connect, and the WireGuard peer configuration its gateways enforce. A
// plain composable kurly.http workload on the project's own image, backed by an
// external PostgreSQL. Import it and render with kurly.list:
//
//   local defguard = import 'github.com/metio/kurly/workloads/defguard/core.libsonnet';
//   kurly.list(defguard())
//
// Serves the web interface and its API on :8000 — compose an exposure onto it.
//
// THIS IS THE CONTROL PLANE, NOT THE VPN. Core holds the accounts and hands each
// gateway its peer list; the gateway that actually carries WireGuard traffic runs
// elsewhere, needs NET_ADMIN and the host's network, and is a separate deployment
// decision from this one. Deploying core alone gives you the directory and the
// admin interface with no tunnel behind them.
//
// COOKIES ARE SECURE BY DEFAULT AND THAT BREAKS PLAIN HTTP. The application marks
// its session cookies Secure, so a browser reaching it over http:// silently
// discards them and the login loop never completes. `cookieInsecure` relaxes that
// for a deployment terminating TLS somewhere the application cannot see — it is
// the wrong answer for anything on a real network.
//
// Enterprise features live in the same repository under a separate licence; the
// image is one build and the licence that applies depends on which features are
// switched on.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './core.image', '\n');

function(
  name='defguard',
  image=defaultImage,
  replicas=1,
  dbHost='defguard-db-rw',
  dbPort=5432,
  dbName='defguard',
  dbUser='defguard',
  // The URL a browser reaches this at; defguard builds its enrollment links and
  // OpenID issuer from it.
  url=null,
  // Relax the Secure flag on session cookies. Only for a deployment that
  // terminates TLS out of the application's sight.
  cookieInsecure=false,
  // A Secret carrying DEFGUARD_DB_PASSWORD, DEFGUARD_AUTH_SECRET,
  // DEFGUARD_YUBIBRIDGE_SECRET, DEFGUARD_GATEWAY_SECRET and
  // DEFGUARD_SECRET_KEY.
  secretName='defguard',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8000)
  + kurly.servicePort(8000)
  + kurly.env(
    {
      DEFGUARD_DB_HOST: dbHost,
      DEFGUARD_DB_PORT: std.toString(dbPort),
      DEFGUARD_DB_NAME: dbName,
      DEFGUARD_DB_USER: dbUser,
    }
    + (if url != null then { DEFGUARD_URL: url } else {})
    + (if cookieInsecure then { DEFGUARD_COOKIE_INSECURE: 'true' } else {})
    + env
  )
  + kurly.envFromSecret(secretName)
  // The image runs as root and owns nothing that needs it; all state is in
  // PostgreSQL, so an unprivileged uid with no volume serves.
  + kurly.runAs(1000, gid=1000)
  + kurly.scratch('/tmp', '128Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
