// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// hortusfox — a HortusFox server (collaborative plant management: what grows where,
// when it was last watered, and the photo log that shows how it is doing). A plain
// composable kurly.http workload on the official image, backed by an external
// MySQL/MariaDB, with its plant photos and attachments on PersistentVolumes. Import
// it, point it at a database, and render with kurly.list:
//
//   local hortusfox = import 'github.com/metio/kurly/workloads/hortusfox/server.libsonnet';
//   kurly.list(hortusfox())
//
// Serves the web app on :80 — compose an exposure onto it.
//
// DATABASE & SECRETS: HortusFox needs a MySQL/MariaDB database — the mysql-cluster
// workload provides one. It reads its database coordinates from env and DB_PASSWORD
// plus APP_ADMIN_PASSWORD (the initial administrator account it seeds on first boot)
// from a provided Secret via envFrom. kurly authors no Secret.
//
// The Apache + PHP image starts as root and binds :80, and the entrypoint takes
// ownership of the mounted directories before dropping to www-data, so this relaxes
// kurly's non-root and read-only-rootfs defaults. The application also writes its
// logs, backups and migration state beside its own code inside the image tree, which
// is what the writable root filesystem covers.
//
// Single writer: photos and attachments live on ReadWriteOnce volumes, so one
// replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='hortusfox',
  image=defaultImage,
  // Plant photos (/var/www/html/public/img).
  storageSize='10Gi',
  // Uploaded attachments (/var/www/html/public/attachments).
  attachmentsStorageSize='5Gi',
  storageClass=null,
  dbHost='hortusfox-db',
  dbPort=3306,
  database='hortusfox',
  dbUser='hortusfox',
  dbCharset='utf8mb4',
  // The initial administrator account seeded on first boot. Its password comes
  // from the Secret, never from the rendered manifest.
  adminEmail='admin@example.com',
  timezone='UTC',
  // The Secret holding DB_PASSWORD and APP_ADMIN_PASSWORD (kurly mints none), via envFrom.
  secretName='hortusfox',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    DB_HOST: dbHost,
    DB_PORT: std.toString(dbPort),
    DB_DATABASE: database,
    DB_USERNAME: dbUser,
    DB_CHARSET: dbCharset,
    APP_ADMIN_EMAIL: adminEmail,
    APP_TIMEZONE: timezone,
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  + kurly.writableRootFilesystem()
  + kurly.store('/var/www/html/public/img', storageSize, storageClass=storageClass)
  + kurly.store('/var/www/html/public/attachments', attachmentsStorageSize, storageClass=storageClass)
  // The first boot runs the schema migrations and seeds the administrator account
  // before Apache answers, so the startup budget is generous and the liveness clock
  // only starts once it has passed. Probing by connection: / redirects to the login.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 60, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
