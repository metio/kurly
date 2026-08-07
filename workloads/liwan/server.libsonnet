// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// liwan — a Liwan server (privacy-first web analytics: a one-line script per site,
// no cookies, no cross-site identifiers, everything kept in an embedded DuckDB
// beside it). A plain composable kurly.http workload keeping that database on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local liwan = import 'github.com/metio/kurly/workloads/liwan/server.libsonnet';
//   kurly.list(liwan(baseUrl='https://analytics.example.com'))
//
// Serves the dashboard, the tracking script and the event API on :9042 — compose
// an exposure onto it.
//
// SET BASEURL BEFORE YOU PUBLISH IT. Liwan does not refuse to start without one:
// it falls back to http://localhost:9042, which is why there is no wrong default
// baked in here. That fallback decides the origin the tracking script is served
// for and whether session cookies are marked secure, so an instance reachable at
// a real name and still carrying the fallback authenticates over an insecure
// cookie and rejects the events its own script sends.
//
// While no user exists, Liwan mints a one-time onboarding token and logs the link
// that redeems it — <baseUrl>/setup?t=… — which is what creates the first
// administrator. The link is built from the base URL, so an unset one logs a
// localhost address; a fresh token is minted on every start until an account
// exists, so a restart is not a lockout.
//
// GEOIP IS OFF unless configured. Country breakdowns come either from a MaxMind
// database (an account and a licence key, LIWAN_MAXMIND_ACCOUNT_ID /
// LIWAN_MAXMIND_LICENSE_KEY) or from headers a proxy in front already sets
// (LIWAN_GEOIP_HEADERS); neither is assumed here.
//
// Visitor IPs are read from the connection unless trusted proxies are named. Every
// request behind an ingress arrives from the ingress controller, so without
// LIWAN_TRUSTED_PROXIES and LIWAN_CLIENT_IP_HEADERS every visitor is grouped as
// one — see the README.
//
// Single writer: one DuckDB database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) — two processes opening the same database file is not
// a thing DuckDB sorts out for you.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='liwan',
  image=defaultImage,
  storageSize='10Gi',
  storageClass=null,
  // The public URL this instance answers on, scheme included. Unset falls back to
  // Liwan's own http://localhost:9042, which is wrong everywhere it is deployed
  // but is the app's default rather than one invented here.
  baseUrl=null,
  logLevel='info',
  // Favicons for the referrer list are fetched from DuckDuckGo, i.e. from a third
  // party, per referring domain. Off by default: an analytics workload that phones
  // out on its own is the opposite of what it is here for.
  disableFavicons=true,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv =
    {
      // The image already sets this; stated so the database follows the volume
      // even if a consumer overrides the image with one that does not.
      LIWAN_DATA_DIR: '/data',
      LIWAN_PORT: '9042',
      LIWAN_DISABLE_FAVICONS: if disableFavicons then 'true' else 'false',
    }
    + (if baseUrl == null then {} else { LIWAN_BASE_URL: baseUrl });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(9042)
  + kurly.servicePort(9042)
  + kurly.args(['--log-level', logLevel])
  + kurly.env(baseEnv + env)
  // A Service named after this workload makes Kubernetes inject LIWAN_PORT as a
  // tcp:// URL, and every LIWAN_* variable in the environment is a configuration
  // override to Liwan.
  + kurly.disableServiceLinks()
  // A single static binary on a distroless base: it selects no account, binds an
  // unprivileged port and writes only under the data directory. The fsGroup is
  // what makes the empty volume writable for it.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  // DuckDB spills to a temporary directory when a query exceeds its memory
  // budget, and the root filesystem is read-only.
  + kurly.scratch('/tmp')
  // The tracking script is static, needs no session and answers 200 without
  // redirecting — unlike the dashboard, which sends an unauthenticated visitor
  // somewhere else.
  + kurly.readinessProbe({ httpGet: { path: '/script.js', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/script.js', port: 'http' } })
  // First start creates the database and runs its migrations before anything
  // listens.
  + kurly.startupProbe({ httpGet: { path: '/script.js', port: 'http' }, periodSeconds: 5, failureThreshold: 60 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
