// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// fittrackee — a FitTrackee server (a self-hosted workout and activity tracker:
// GPX/FIT uploads, maps, statistics). A plain composable kurly.http workload
// backed by an EXTERNAL PostgreSQL that MUST have the PostGIS extension — v1+
// stores geospatial data, and on a plain PostgreSQL the start-up migration fails
// and the pod restarts forever. Uploaded activity files and pictures live on a
// PersistentVolume. Import it, point it at a database, and render with kurly.list:
//
//   local fittrackee = import 'github.com/metio/kurly/workloads/fittrackee/server.libsonnet';
//   kurly.list(fittrackee(uiUrl='https://fittrackee.example.com'))
//
// Serves the web app and API on :5000 — compose an exposure onto it.
//
// DATABASE, CACHE & SECRETS: DATABASE_URL carries the password, so it comes from a
// provided Secret via envFrom together with APP_SECRET_KEY (which signs sessions).
// kurly authors no Secret. Redis is OPTIONAL — without it the API rate limits, the
// background workers (data export, archive upload) and e-mail are simply off; the
// application notices at start-up and carries on. redisUrl points at one when there
// is one (a valkey named fittrackee-cache is the obvious neighbour).
//
// uiUrl is the origin a browser reaches this instance at, and the application
// REFUSES TO START without it. It ends up in the e-mails and feeds it generates, so
// the placeholder default is a value to replace, not one to deploy.
//
// The image ships no CMD: its entrypoint is tini, and the start-up script that
// migrates the database and then execs gunicorn is passed as arguments.
//
// Single writer: uploads and the static-map cache live on a ReadWriteOnce volume,
// so one replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='fittrackee',
  image=defaultImage,
  // Uploaded activity files, pictures and the static-map cache.
  storageSize='10Gi',
  storageClass=null,
  // The origin a browser reaches this instance at. Baked into generated e-mails
  // and feeds — and the application does not start without it.
  uiUrl='https://fittrackee.example.com',
  // An optional Redis/valkey for rate limits, background workers and e-mail.
  redisUrl=null,
  // Gunicorn workers inside the single pod.
  workers=1,
  // The Secret holding DATABASE_URL (with the embedded database password) and
  // APP_SECRET_KEY. kurly mints none.
  secretName='fittrackee',
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(5000)
  + kurly.servicePort(5000)
  // tini is the entrypoint and the image declares no command, so the start-up
  // script — `ftcli db upgrade` and then gunicorn — is passed as arguments.
  + kurly.args(['sh', 'docker-entrypoint.sh'])
  + kurly.env(
    {
      APP_SETTINGS: 'fittrackee.config.ProductionConfig',
      UI_URL: uiUrl,
      // The application appends `uploads` to this, and Static Map 3 reads its
      // cache directory from its own variable; both land on the volume.
      UPLOAD_FOLDER: '/data',
      STATICMAP_CACHE_DIR: '/data/staticmap_cache',
      // gunicorn's error log defaults to a file in a directory the image does not
      // contain; a single dash is its own spelling of stderr.
      GUNICORN_LOG: '-',
      APP_WORKERS: std.toString(workers),
    }
    + (if redisUrl == null then {} else { REDIS_URL: redisUrl })
    + env
  )
  + kurly.envFromSecret(secretName)
  // The image runs as the unprivileged `fittrackee` account (uid/gid 1000); the
  // fsGroup is what lets that account write the volume it is given.
  + kurly.runAs(1000, 1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  // Werkzeug spools an upload through a temporary file before the application
  // moves it onto the volume.
  + kurly.scratch('/tmp', '512Mi')
  // The database is migrated before gunicorn binds anything, so the first start of
  // an empty instance answers nothing for a while.
  + kurly.startupProbe({ httpGet: { path: '/api/ping', port: 'http' }, failureThreshold: 60, periodSeconds: 10 })
  + kurly.readinessProbe({ httpGet: { path: '/api/check-db', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/ping', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
