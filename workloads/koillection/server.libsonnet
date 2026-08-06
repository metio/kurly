// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// koillection — a Koillection server (a collection manager: whatever you collect,
// described with the fields you decide it has, plus wishlists, loans and a tag
// index). A composable kurly.http workload backed by an EXTERNAL PostgreSQL — the
// cnpg-cluster workload provides one — with uploaded images on a PersistentVolume.
// Import it and render with kurly.list:
//
//   local koillection = import 'github.com/metio/kurly/workloads/koillection/server.libsonnet';
//   kurly.list(koillection())
//
// Serves the web app on :80 — compose an exposure onto it.
//
// Single writer: uploads on a ReadWriteOnce volume, so one replica, recreated
// (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='koillection',
  image=defaultImage,
  // Uploaded photos and thumbnails, mounted at /uploads.
  storageSize='10Gi',
  storageClass=null,
  // The PostgreSQL it connects to. The coordinates are env; the password lives in
  // the Secret. DB_VERSION is the server version Doctrine generates SQL for.
  dbHost='koillection-db-rw',
  dbPort=5432,
  database='koillection',
  dbUser='koillection',
  dbVersion='16',
  // Which origins the JSON API answers cross-origin. The image's own default only
  // allows localhost, which is right until somebody writes a browser client.
  corsAllowOrigin='^https?://(localhost|127[.]0[.]0[.]1)(:[0-9]+)?$',
  // Largest file the upload form and PHP accept.
  uploadMaxFilesize='100M',
  // Sets PHP's session.cookie_secure. True is right behind TLS and wrong in front
  // of plain HTTP, where the browser then discards the session cookie and nobody
  // can stay logged in.
  httpsEnabled=true,
  // The Secret holding DB_PASSWORD, APP_SECRET and JWT_PASSPHRASE. The entrypoint
  // invents the latter two with `openssl rand` when they are unset, which reads as
  // a safe default and is not: they are regenerated on every restart, so sessions
  // and API tokens are invalidated whenever the pod moves.
  secretName='koillection',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '768Mi' } },
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
    {
      APP_ENV: 'prod',
      APP_DEBUG: '0',
      DB_DRIVER: 'pdo_pgsql',
      DB_HOST: dbHost,
      DB_PORT: std.toString(dbPort),
      DB_NAME: database,
      DB_USER: dbUser,
      DB_VERSION: std.toString(dbVersion),
      CORS_ALLOW_ORIGIN: corsAllowOrigin,
      UPLOAD_MAX_FILESIZE: uploadMaxFilesize,
      HTTPS_ENABLED: if httpsEnabled then '1' else '0',
    } + env
  )
  + kurly.envFromSecret(secretName)
  // The entrypoint runs usermod/groupmod, chowns /uploads and starts php-fpm and
  // nginx, which it can only do from root; nginx also binds :80.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  // Everything the application writes lives inside its own tree: the generated
  // .env.local, the Symfony cache and logs, the JWT keypair, the php-fpm and nginx
  // runtime files.
  + kurly.writableRootFilesystem()
  + kurly.store('/uploads', storageSize, storageClass=storageClass)
  // nginx only starts once the database migration and the JWT keypair are done, so
  // a connection to :80 is the honest readiness signal — and the first start has to
  // migrate before it gets there. The app answers / with a redirect to the login
  // page, so probing it by path would fail on the redirect.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 60, periodSeconds: 5 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
