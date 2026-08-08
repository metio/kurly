// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// eonvelope — an Eonvelope server (a Django application that fetches mail over
// IMAP, POP, Exchange or JMAP and keeps it, with its attachments and
// correspondents, searchable for as long as you care to keep it). A composable
// kurly.http workload backed by an EXTERNAL MySQL/MariaDB — the mysql-cluster
// workload provides one — with the archive itself on a PersistentVolume. Import
// it and render with kurly.list:
//
//   local eonvelope = import 'github.com/metio/kurly/workloads/eonvelope/server.libsonnet';
//   kurly.list(eonvelope())
//
// IT SPEAKS HTTPS, NOT HTTP. gunicorn binds :443 with the self-signed certificate
// the image bakes in, so an exposure in front of it must talk TLS to the backend
// (a backend-protocol annotation on an Ingress, a BackendTLSPolicy on an
// HTTPRoute) and must not verify that certificate against a public CA. Probes go
// by connection for the same reason, and because Django answers a request whose
// Host is not in ALLOWED_HOSTS with 400.
//
// ALLOWED_HOSTS defaults to '*'. Django refuses every request otherwise, and a
// workload that cannot be reached until a parameter is set is a workload nobody
// can boot; name the real hosts once the instance has an address.
//
// ONE CONTAINER RUNS SEVERAL SERVICES. s6-overlay supervises the web server, a
// RabbitMQ broker, the celery worker and beat, the database migrations and the
// creation of the initial admin account — so the pod runs as root, may raise
// privileges and keeps its capabilities, and its root filesystem is writable
// (RabbitMQ, gunicorn's access log and Django all write inside the image's tree).
// A first boot migrates the database and starts a broker, so the startup budget
// is generous.
//
// Single writer: the archive lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='eonvelope',
  image=defaultImage,
  // The archived mail and its attachments.
  storageSize='20Gi',
  storageClass=null,
  // The MySQL/MariaDB it connects to. The coordinates are env; the password lives
  // in the Secret.
  dbHost='eonvelope-db',
  dbPort=3306,
  database='email_archive_django',
  dbUser='eonvelope',
  // PostgreSQL and SQLite are supported too — 'postgresql' or 'sqlite3'.
  databaseType='mysql',
  // Every host name the instance answers on, comma separated.
  allowedHosts='*',
  // The Secret holding SECRET_KEY, DATABASE_PASSWORD and DJANGO_SUPERUSER_PASSWORD.
  // All three have published defaults in the project's own compose file, the
  // session-signing key and the admin password included, so supplying them is the
  // difference between an archive of your mail and everybody's.
  secretName='eonvelope',
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '3Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(443)
  + kurly.servicePort(443)
  + kurly.env(
    {
      DATABASE: database,
      DATABASE_USER: dbUser,
      DATABASE_TYPE: databaseType,
      DATABASE_HOST: dbHost,
      DATABASE_PORT: std.toString(dbPort),
      ALLOWED_HOSTS: allowedHosts,
    } + env
  )
  + kurly.envFromSecret(secretName)
  // s6-overlay supervises the web server, the broker, celery and the one-shot
  // migration and superuser steps, and drops privileges to their accounts, which
  // it can only do from root. gunicorn also binds :443.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  // RabbitMQ keeps its mnesia directory, gunicorn its access log and Django its
  // runtime files inside the image's own tree.
  + kurly.writableRootFilesystem()
  + kurly.store('/mnt/archive', storageSize, storageClass=storageClass)
  // Migrations, the broker and the first admin account all happen before anything
  // listens.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 60, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
