// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// bracket — a Bracket API server (runs competition tournaments: clubs, teams,
// players, courts and the brackets and swiss rounds that decide them). A composable
// kurly.http workload on the backend image, backed by an EXTERNAL PostgreSQL — the
// cnpg-cluster workload provides one — with uploaded club and team logos on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local bracket = import 'github.com/metio/kurly/workloads/bracket/server.libsonnet';
//   kurly.list(bracket())
//
// Serves the API on :8400 — compose an exposure onto it. This is the BACKEND image:
// it answers the API and serves the uploaded logos under /static, and nothing else.
// The web frontend is a separate image and is not carried here.
//
// Single writer: the uploaded logos live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='bracket',
  image=defaultImage,
  // Uploaded tournament and team logos.
  storageSize='2Gi',
  storageClass=null,
  // The public URL the API is reached at. Left unset by default, because the value
  // that is right here is wrong everywhere else; the application then falls back to
  // its own http://localhost:8400, which is fine in-cluster and not for SSO links.
  baseUrl=null,
  // The browser origins allowed to call the API — the frontend's URL. The
  // application's own default is '*', which it warns about in production.
  corsOrigins=null,
  // The administrator created on the first start, with the ADMIN_PASSWORD in the
  // Secret. NOT optional the way it reads: an empty database is only ever populated
  // by the branch that creates this account, and without it the Alembic run that
  // follows tries to drop an index no table has and the process exits.
  adminEmail='admin@example.com',
  // The Secret holding PG_DSN (the whole postgresql:// connection string),
  // JWT_SECRET (which signs the tokens users hold) and ADMIN_PASSWORD.
  secretName='bracket',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8400)
  + kurly.servicePort(8400)
  + kurly.env(
    {
      ENVIRONMENT: 'PRODUCTION',
      ADMIN_EMAIL: adminEmail,
      // The interpreter cannot write bytecode next to its own code on a read-only
      // root filesystem; saying so keeps it from trying on every import.
      PYTHONDONTWRITEBYTECODE: '1',
    }
    + (if baseUrl == null then {} else { BASE_URL: baseUrl })
    + (if corsOrigins == null then {} else { CORS_ORIGINS: corsOrigins })
    + env
  )
  + kurly.envFromSecret(secretName)
  // The image's own account, and the group the uploaded logos must belong to for it
  // to write them.
  + kurly.runAs(100, gid=101, fsGroup=101)
  + kurly.store('/app/static', storageSize, storageClass=storageClass)
  // pipenv resolves the virtualenv on every start and writes its caches under the
  // account's home; gunicorn and the upload handler use /tmp.
  + kurly.scratch('/home/bracket/.cache', '64Mi')
  + kurly.scratch('/tmp', '64Mi')
  // The first start runs the Alembic migrations before the API answers.
  + kurly.startupProbe({ httpGet: { path: '/ping', port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ httpGet: { path: '/ping', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/ping', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
