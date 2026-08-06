// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// part-db — a Part-DB server (an inventory for electronic components: what parts
// you have, how many are left, where they sit, and the datasheets that belong to
// them). A plain composable kurly.http workload on the official image, keeping its
// SQLite database, attachments and public media on PersistentVolumes. Import it and
// render with kurly.list:
//
//   local partdb = import 'github.com/metio/kurly/workloads/part-db/server.libsonnet';
//   kurly.list(partdb())
//
// Serves the web app on :80 — compose an exposure onto it.
//
// DATABASE: the image defaults to SQLite inside the uploads volume, which is why
// this workload needs nothing external to start. Point databaseUrl at a MySQL or
// PostgreSQL instead (the image carries both PDO drivers) — mysql://… or
// postgresql://… — and pass the credentials through a Secret with envFrom rather
// than a literal URL if they must not sit in the rendered manifest.
//
// Apache and php-fpm start as root, bind :80 and let the entrypoint chown the
// volumes before dropping to www-data, so this relaxes kurly's non-root and
// read-only-rootfs defaults; Symfony also warms its cache into /var/www/html/var
// inside the image's own tree.
//
// Single writer: the database and the attachments live on ReadWriteOnce volumes, so
// one replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='part-db',
  image=defaultImage,
  // Attachments and, by default, the SQLite database (/var/www/html/uploads).
  storageSize='5Gi',
  // Publicly served media, e.g. rendered part pictures (/var/www/html/public/media).
  mediaStorageSize='2Gi',
  storageClass=null,
  // Doctrine DSN. null keeps the image's SQLite file inside the uploads volume.
  databaseUrl=null,
  // Displayed as the instance's name in the UI.
  instanceName='Part-DB',
  defaultLanguage='en',
  defaultTimezone='UTC',
  baseCurrency='EUR',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    INSTANCE_NAME: instanceName,
    DEFAULT_LANG: defaultLanguage,
    DEFAULT_TIMEZONE: defaultTimezone,
    BASE_CURRENCY: baseCurrency,
  } + (if databaseUrl == null then {} else { DATABASE_URL: databaseUrl });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env(baseEnv + env)
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  + kurly.writableRootFilesystem()
  + kurly.store('/var/www/html/uploads', storageSize, storageClass=storageClass)
  + kurly.store('/var/www/html/public/media', mediaStorageSize, storageClass=storageClass)
  // The first boot runs the Doctrine migrations and warms the Symfony cache before
  // Apache answers, so the startup budget is generous and the liveness clock only
  // starts once it has passed. Probing by connection: / redirects to /login.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 60, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
