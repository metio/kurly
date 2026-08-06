// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mayan-edms — a Mayan EDMS server (a document management system: it ingests
// scans and files, generates previews, OCRs them, and files them away under
// cabinets, tags and metadata indexes that are rebuilt as documents arrive). A
// composable kurly.http workload running the official all-in-one image: gunicorn
// and the five Celery worker classes under one supervisord, with the document
// store on a PersistentVolume and PostgreSQL and Redis external. Import it, point
// it at a database and a broker, and render with kurly.list:
//
//   local mayan = import 'github.com/metio/kurly/workloads/mayan-edms/server.libsonnet';
//   kurly.list(mayan())
//
// Serves the UI and API on :8000 — compose an exposure onto it.
//
// DATABASE & CACHE: Mayan needs PostgreSQL and a Redis broker. This pairs with
// the cnpg-cluster and valkey workloads — the defaults point at a CNPG cluster
// named `mayan-edms-db` (its `-rw` Service) and a Valkey named
// `mayan-edms-cache`.
//
// SECRETS: a consumer-provided Secret is read as environment. It holds
// MAYAN_DATABASE_PASSWORD and the two Celery URLs
// (MAYAN_CELERY_BROKER_URL / MAYAN_CELERY_RESULT_BACKEND, each carrying the
// Redis password). kurly authors no Secret; fill it with kurly.externalSecret.
//
// Django takes its database as ONE setting, MAYAN_DATABASES — a dict holding the
// password inline — which is why the connection is assembled by the image's own
// MAYAN_DOCKER_SCRIPT_PRE_SETUP hook from the separate variables above rather
// than written here: a literal dict in this file would put the password in the
// rendered manifest.
//
// ROOT: the entrypoint chowns the document store and then drops to the `mayan`
// account with runuser, which it can only do as root, so root, privilege
// escalation and capabilities are relaxed; supervisord, gunicorn and the font
// cache all write inside the image's own tree, so the root filesystem is
// writable too.
//
// Single writer: one PersistentVolume holds every document, so this is one
// replica, recreated (never rolled) to keep two pods off the ReadWriteOnce
// volume.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='mayan-edms',
  image=defaultImage,
  // Documents, their previews, caches and the generated SECRET_KEY.
  storageSize='20Gi',
  storageClass=null,
  // The PostgreSQL it connects to. The non-secret coordinates are env; the
  // password comes from the Secret and is assembled into MAYAN_DATABASES inside
  // the container.
  dbHost='mayan-edms-db-rw',
  dbPort=5432,
  database='mayan',
  dbUser='mayan',
  // The Secret read as environment: MAYAN_DATABASE_PASSWORD,
  // MAYAN_CELERY_BROKER_URL and MAYAN_CELERY_RESULT_BACKEND.
  secretName='mayan-edms',
  // gunicorn workers inside the pod. Every Celery worker class runs in the same
  // container, so this is the front end's share of it.
  workers=3,
  // Extra environment (MAYAN_WORKER_*_CONCURRENCY, MAYAN_LOCK_MANAGER_BACKEND,
  // MAYAN_DOCKER_WAIT, …), merged over the below. Anything sensitive belongs in
  // the Secret, not a literal here.
  env={},
  resources={ requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '3Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    MAYAN_DATABASE_HOST: dbHost,
    MAYAN_DATABASE_PORT: std.toString(dbPort),
    MAYAN_DATABASE_NAME: database,
    MAYAN_DATABASE_USER: dbUser,
    MAYAN_GUNICORN_WORKERS: std.toString(workers),
    // The entrypoint evaluates this before anything else starts, and everything
    // it starts inherits the export — so the one setting Django wants is built
    // where the password already is, instead of being rendered into a manifest.
    MAYAN_DOCKER_SCRIPT_PRE_SETUP: |||
      export MAYAN_DATABASES="{'default':{'ENGINE':'django.db.backends.postgresql','NAME':'$MAYAN_DATABASE_NAME','USER':'$MAYAN_DATABASE_USER','PASSWORD':'$MAYAN_DATABASE_PASSWORD','HOST':'$MAYAN_DATABASE_HOST','PORT':'$MAYAN_DATABASE_PORT'}}"
    |||,
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8000)
  + kurly.servicePort(8000)
  + kurly.env(baseEnv + env)
  + kurly.envFromSecret(secretName)
  // A Service named after this workload would otherwise inject MAYAN_EDMS_PORT
  // as a tcp:// URL, and Mayan reads every MAYAN_-prefixed variable as one of
  // its own settings.
  + kurly.disableServiceLinks()
  // The entrypoint chowns the document store and starts every process through
  // runuser, both of which need root and the identity capabilities.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  // supervisord's logs and sockets, gunicorn's worker files and the font cache
  // the entrypoint builds all land inside the image's own tree.
  + kurly.writableRootFilesystem()
  + kurly.store('/var/lib/mayan', storageSize, storageClass=storageClass)
  // The first boot runs the whole Django migration set, builds the font cache and
  // installs the initial document types before gunicorn binds anything, which
  // takes minutes; probe by connection, because / redirects to the login page.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 15, failureThreshold: 60 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' }, periodSeconds: 15 })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' }, initialDelaySeconds: 60, periodSeconds: 30 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
