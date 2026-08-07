// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// libredb-studio — a LibreDB Studio server (a browser SQL client for PostgreSQL,
// MySQL, SQLite, MongoDB, Redis and more: browse schemas, run queries and keep an
// audit trail without installing a desktop client). A plain composable kurly.http
// workload. Import it and render with kurly.list:
//
//   local libredb = import 'github.com/metio/kurly/workloads/libredb-studio/server.libsonnet';
//   kurly.list(libredb())
//
// Serves the web app on :3000 — compose an exposure onto it.
//
// It is a client for databases, not a database: the servers it connects to are
// entered by a user at runtime and are not dependencies of this workload. Its own
// state — accounts, saved connections, query history — goes into a SQLite file on
// the volume, which is what STORAGE_PROVIDER=sqlite selects; the image's own
// default keeps that state in the browser instead, so it would be lost with the
// tab and nothing would be shared between users.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='libredb-studio',
  image=defaultImage,
  storageSize='2Gi',
  storageClass=null,
  // The Secret holding JWT_SECRET (which signs the tokens users hold) and
  // ADMIN_PASSWORD (the first account). Left unset in the environment, the app
  // generates both on first start and writes them to /app/data — which survives a
  // restart here, since that directory is the volume, but not a move to a fresh
  // one, and the password is then only in a log line that has scrolled away.
  secretName='libredb-studio',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '768Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.env(
    {
      STORAGE_PROVIDER: 'sqlite',
      STORAGE_SQLITE_PATH: '/app/data/libredb-storage.db',
    } + env
  )
  + kurly.envFromSecret(secretName)
  // The image provisions uid/gid 1001 (nextjs:nodejs) and its entrypoint drops to
  // that account with gosu when it starts as root. Naming the account here means
  // there is no root phase to drop out of: the entrypoint sees a non-root uid and
  // execs straight through, so the hardened posture holds and the volume is
  // writable because fsGroup owns it.
  + kurly.runAs(1001, gid=1001, fsGroup=1001)
  + kurly.store('/app/data', storageSize, storageClass=storageClass)
  // Next.js writes its response cache beside its own build output, which is inside
  // the read-only install tree, and node writes temporary files under /tmp.
  + kurly.scratch('/app/.next/cache')
  + kurly.scratch('/tmp')
  // /api/db/health answers without authentication and reports the storage backend,
  // so it says the SQLite file is open rather than merely that the port is bound.
  // A Next.js server compiles its first routes on demand, so the startup probe is
  // what buys that time; a liveness probe generous enough for it would take just as
  // long to notice a hung server later.
  + kurly.startupProbe({ httpGet: { path: '/api/db/health', port: 'http' }, failureThreshold: 30, periodSeconds: 5 })
  + kurly.readinessProbe({ httpGet: { path: '/api/db/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/db/health', port: 'http' }, periodSeconds: 30, failureThreshold: 6 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
