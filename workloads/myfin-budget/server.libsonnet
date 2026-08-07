// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// myfin-budget — the MyFin API server (the backend of a personal finance
// platform: budgets, accounts, transactions and forecasts). A composable
// kurly.http workload backed by an EXTERNAL MySQL/MariaDB — the mysql-cluster
// workload provides one — and holding no state of its own. Import it and render
// with kurly.list:
//
//   local myfin = import 'github.com/metio/kurly/workloads/myfin-budget/server.libsonnet';
//   kurly.list(myfin())
//
// Serves the REST API on :3001 — compose an exposure onto it. The browser client
// is a separate static bundle that talks to this API; it is not part of this
// workload.
//
// The database connection comes from a provided Secret via envFrom: DATABASE_URL
// is read first and, if it is absent, assembled from DB_NAME/DB_USER/DB_PW/
// DB_HOST/DB_PORT. kurly authors no Secret. The same Secret is the place for the
// SMTP credentials, which the OTP and password-reset mails need.
//
// Stateless: everything lives in MySQL, so this is a plain rolling Deployment.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='myfin-budget',
  image=defaultImage,
  // The migrations take an advisory lock, so several replicas start safely — one
  // of them runs them and the rest wait.
  replicas=1,
  // The Secret holding DATABASE_URL (or the DB_* parts it is assembled from) and,
  // for the mails the platform sends, SMTP_HOST/SMTP_PORT/SMTP_SECURE/SMTP_USER/
  // SMTP_PASSWORD/SMTP_FROM.
  secretName='myfin-budget',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(3001)
  + kurly.servicePort(3001)
  + kurly.env(
    {
      NODE_ENV: 'production',
      // Stated explicitly so the declared container port cannot drift from the one
      // the process binds.
      PORT: '3001',
      // The command line is `npm run db:deploy && node dist/server.js`, and npm
      // insists on a writable home and cache before it runs anything.
      HOME: '/tmp',
      npm_config_cache: '/tmp/.npm',
      npm_config_update_notifier: 'false',
    } + env
  )
  + kurly.envFromSecret(secretName)
  // The image ships the node account as 1000:1000 and owns nothing outside /tmp,
  // so the hardened default holds.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // npm and the Prisma CLI write under /tmp; a scratch there keeps the rest of the
  // root filesystem read-only.
  + kurly.scratch('/tmp')
  // The first start applies the Prisma migration ladder against the database and
  // only then listens, which is what needs a startup budget rather than a longer
  // liveness delay. GET / answers 200 with the API's own version once it does.
  + kurly.startupProbe({ httpGet: { path: '/', port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
