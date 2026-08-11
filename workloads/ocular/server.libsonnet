// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// ocular — an Ocular server (a budgeting app that tracks spending and budgets across months
// and years, with dashboard analytics, imports from Google Sheets and JSON export). A
// composable kurly.http workload on the official image. Import it and render with kurly.list:
//
//   local ocular = import 'github.com/metio/kurly/workloads/ocular/server.libsonnet';
//   kurly.list(ocular())
//
// Serves the web app on :80 — compose an exposure onto it.
//
// ONE CONTAINER, TWO PROCESSES: the entrypoint starts the `genesis` backend on :8080 and a
// Caddy in front of it on :80, which serves the built single-page app and proxies /api/* to
// the backend. Only :80 is worth a Service; :8080 is never reached from outside the pod.
//
// Single writer: accounts and budgets live in the backend's own database file under /data,
// on a ReadWriteOnce volume — so one replica, recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='ocular',
  image=defaultImage,
  // Accounts and their budget data (GENESIS_DB_PATH is /data/genesis), plus Caddy's own
  // state under the same XDG_DATA_HOME.
  storageSize='1Gi',
  storageClass=null,
  // How long an issued session token stays valid, in HOURS. The image sets no
  // default for it and the backend parses it unconditionally, so leaving it out
  // is fatal rather than merely unconfigured (see below).
  tokenExpiration=720,
  // The Secret holding GENESIS_JWT_SECRET, which signs those tokens. Rotating it
  // signs everybody out; sharing it lets somebody else mint a session.
  secretName='ocular',
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  // GENESIS_JWT_TOKEN_EXPIRATION IS REQUIRED AND UNSET IN THE IMAGE. The backend
  // parses it during package initialisation, before anything is configured, so an
  // absent value is not defaulted — it panics with "strconv.ParseInt: parsing \"\":
  // invalid syntax" and a stack in core/config.go, naming no variable at all. Every
  // OTHER integer the image documents is set in its own environment, which is what
  // makes the empty one so hard to find: the answer is the one name that is missing
  // rather than any of the ones present.
  + kurly.env({ GENESIS_JWT_TOKEN_EXPIRATION: std.toString(tokenExpiration) } + env)
  + kurly.envFromSecret(secretName)
  // The image declares root and the entrypoint drops nothing, so the user is pinned here;
  // fsGroup is what makes the volume writable for the backend's database.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // Caddy's binary carries the file capability cap_net_bind_service, and a file with
  // permitted capabilities cannot be exec'd at all once the bounding set drops them: the
  // kernel refuses with `operation not permitted`, which reads as a broken image rather
  // than a dropped capability. It is also what lets it bind :80 as an ordinary user.
  + kurly.addCapabilities(['NET_BIND_SERVICE'])
  // XDG_DATA_HOME: the backend's database under /data/genesis and Caddy's state under
  // /data/caddy.
  + kurly.store('/data', storageSize, storageClass=storageClass)
  // XDG_CONFIG_HOME: Caddy's admin API autosaves the running config there. Nothing worth
  // keeping, but the write has to land somewhere for the read-only root filesystem.
  + kurly.scratch('/config')
  // The backend answers /health, which Caddy exposes at /api/health after stripping the
  // prefix — so a probe on it proves both processes, not just the static file server.
  + kurly.startupProbe({ httpGet: { path: '/api/health', port: 'http' }, failureThreshold: 30, periodSeconds: 5 })
  + kurly.readinessProbe({ httpGet: { path: '/api/health', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
