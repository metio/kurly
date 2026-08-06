// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// librebooking — a LibreBooking server (resource and room scheduling: who booked
// which room, meeting space or piece of equipment, and when). A composable
// kurly.http workload backed by an EXTERNAL MySQL/MariaDB — the mysql-cluster
// workload provides one — with its generated configuration and its uploaded
// images and attachments on PersistentVolumes. Import it and render with
// kurly.list:
//
//   local librebooking = import 'github.com/metio/kurly/workloads/librebooking/server.libsonnet';
//   kurly.list(librebooking(scriptUrl='https://booking.example.com/Web'))
//
// Serves the web app on :8080 — compose an exposure onto it.
//
// DATABASE & SECRETS: the schema is created by LibreBooking's own installer at
// /Web/install/, which is guarded by LB_INSTALL_PASSWORD; the database
// coordinates come from env and the two passwords from a provided Secret via
// envFrom. kurly authors no Secret.
//
// The entrypoint rewrites the configuration it links into the install tree and
// links each plugin's config beside its code, so the root filesystem is writable
// while the rest of the hardened posture (non-root, no privilege escalation, all
// capabilities dropped) stands: the image already runs as www-data.
//
// Single writer: configuration and uploads live on ReadWriteOnce volumes, so one
// replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='librebooking',
  image=defaultImage,
  // config.php plus each plugin's configuration, generated on first boot and
  // edited in place from then on.
  storageSize='1Gi',
  // Uploaded resource images, terms-of-service documents and reservation
  // attachments, written under the application's own document root.
  uploadsSize='5Gi',
  storageClass=null,
  // The MySQL/MariaDB it connects to. The non-secret coordinates are env; the
  // password lives in the Secret.
  dbHost='librebooking-db',
  database='librebooking',
  dbUser='librebooking',
  // The absolute URL of the application's Web directory. LibreBooking builds
  // every link and every e-mail against it, so a wrong value survives until
  // somebody clicks a mail — there is no default that is right anywhere.
  scriptUrl=null,
  // The timezone reservations are entered and displayed in.
  timezone='UTC',
  // Logging goes to the folder the entrypoint tails onto stdout; 'none' keeps
  // the application quiet, 'DEBUG' is what the project asks for in a bug report.
  logLevel='none',
  // The Secret holding LB_DATABASE_PASSWORD and LB_INSTALL_PASSWORD. The install
  // password guards the installer that creates and upgrades the schema, so it is
  // as load-bearing as the database credential.
  secretName='librebooking',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  // Apache is configured to listen on 8080 so it can bind as an unprivileged user.
  + kurly.port(8080)
  + kurly.servicePort(80)
  + kurly.env(
    {
      LB_DATABASE_HOSTSPEC: dbHost,
      LB_DATABASE_NAME: database,
      LB_DATABASE_USER: dbUser,
      LB_DEFAULT_TIMEZONE: timezone,
      LB_LOGGING_FOLDER: '/var/log/librebooking',
      LB_LOGGING_LEVEL: logLevel,
      LB_LOGGING_SQL: 'false',
    }
    + (if scriptUrl == null then {} else { LB_SCRIPT_URL: scriptUrl })
    + env
  )
  + kurly.envFromSecret(secretName)
  // The image runs as www-data (33) in the root group, which is what its own
  // files and its log folder are group-writable for; the volumes join it so the
  // same account owns what it writes.
  + kurly.runAs(33, 0, fsGroup=33)
  // The entrypoint copies config.dist.php into place, links it and every plugin
  // configuration back into /var/www/html, restores .htaccess and writes a php
  // ini for the timezone — all inside the image's own tree.
  + kurly.writableRootFilesystem()
  + kurly.store('/config', storageSize, storageClass=storageClass)
  + kurly.store('/var/www/html/Web/uploads', uploadsSize, storageClass=storageClass)
  // A Service named after the workload would otherwise inject LIBREBOOKING_PORT
  // as a tcp:// URL into the pod.
  + kurly.disableServiceLinks()
  // Every path answers a redirect to the installer until the schema exists, so
  // readiness is by connection, not by status code.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
