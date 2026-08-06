// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// adventurelog — an AdventureLog backend (a travel log: the places you have been,
// the trips you are planning, and the photos, dates and map positions that go with
// them). A composable kurly.http workload backed by an EXTERNAL PostgreSQL with
// the PostGIS extension — the application is a GeoDjango project and will not
// start against a plain PostgreSQL — with uploaded photos on a PersistentVolume.
// Import it and render with kurly.list:
//
//   local adventurelog = import 'github.com/metio/kurly/workloads/adventurelog/server.libsonnet';
//   kurly.list(adventurelog(publicUrl='https://adventurelog.example.com'))
//
// Serves the API, the Django admin and the uploaded media on :80 — nginx fronts
// gunicorn inside the pod — so compose an exposure onto it. The SvelteKit web
// front end is a SEPARATE image and is not carried here; it is pointed at this
// one's public origin.
//
// publicUrl is the origin this backend is reached at from a browser. It is baked
// into the media URLs the API hands out and is half of what CSRF is validated
// against, so a wrong value shows an application that loads and cannot save.
//
// Single writer: uploaded photos on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='adventurelog',
  image=defaultImage,
  // Uploaded photos and attachments.
  storageSize='10Gi',
  storageClass=null,
  // The PostgreSQL it connects to. It must have PostGIS available: the models are
  // GeoDjango models and the first migration creates the extension.
  dbHost='adventurelog-db-rw',
  dbPort=5432,
  database='adventurelog',
  dbUser='adventurelog',
  // The origin a browser reaches this backend at, protocol included. Baked into
  // the media URLs the API returns and validated against for CSRF.
  publicUrl='https://adventurelog.example.com',
  // The origin the web front end is served from. Empty leaves the backend's own
  // origin as the only one trusted.
  frontendUrl='https://adventurelog.example.com',
  // Extra origins Django accepts state-changing requests from, on top of
  // publicUrl and frontendUrl.
  csrfTrustedOrigins=[],
  // The first administrator, created on start if it does not exist. Its password
  // comes from the Secret.
  adminUsername='admin',
  adminEmail='admin@example.com',
  // Whether new accounts may be created through the sign-up form.
  disableRegistration=false,
  // The Secret holding POSTGRES_PASSWORD, SECRET_KEY and DJANGO_ADMIN_PASSWORD.
  // All three have published defaults in the project's own compose file, the
  // session-signing key included, so supplying them is not hardening — it is the
  // difference between having accounts and not.
  secretName='adventurelog',
  // Extra environment (EMAIL_*, GOOGLE_MAPS_API_KEY, STRAVA_*, …), merged over the
  // below. Anything sensitive belongs in the Secret, not a literal here.
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local origins = [publicUrl] + (if frontendUrl == null || frontendUrl == '' then [] else [frontendUrl]) + csrfTrustedOrigins;

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env(
    {
      PGHOST: dbHost,
      PGPORT: std.toString(dbPort),
      PGDATABASE: database,
      PGUSER: dbUser,
      // The entrypoint waits for the database with psql and reads the POSTGRES_*
      // names, while Django reads the PG* ones; both have to be set or the pod
      // either never leaves the wait loop or leaves it and cannot connect.
      POSTGRES_DB: database,
      POSTGRES_USER: dbUser,
      PUBLIC_URL: publicUrl,
      FRONTEND_URL: frontendUrl,
      CSRF_TRUSTED_ORIGINS: std.join(',', std.uniq(std.sort(origins))),
      DJANGO_ADMIN_USERNAME: adminUsername,
      DJANGO_ADMIN_EMAIL: adminEmail,
      DEBUG: 'False',
      DISABLE_REGISTRATION: (if disableRegistration then 'True' else 'False'),
    } + env
  )
  + kurly.envFromSecret(secretName)
  // supervisord runs nginx, memcached and gunicorn together and drops privileges
  // to their accounts, which it can only do from root; nginx also binds :80.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  // nginx, memcached and supervisord keep their pid files, logs and temporary
  // request bodies inside the image's own tree, and Django writes its collected
  // static files beside its code.
  + kurly.writableRootFilesystem()
  + kurly.store('/code/media', storageSize, storageClass=storageClass)
  // The first start applies the whole Django migration set, creates the PostGIS
  // extension and downloads the world region dataset before anything answers, so
  // gate on a long startup probe rather than a long liveness delay. Probed by
  // connection: every path either redirects or answers 403 unauthenticated.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 90 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' }, periodSeconds: 15 })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' }, initialDelaySeconds: 60, periodSeconds: 30 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
