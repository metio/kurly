// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// redaxo — a REDAXO server (a content management system built around a structured
// editor: articles composed from typed modules rather than a single rich-text field)
// on the project's own image, backed by an EXTERNAL MySQL/MariaDB — the mysql-cluster
// workload provides one — with the whole application tree on a PersistentVolume.
// Import it, point it at a database, and render with kurly.list:
//
//   local redaxo = import 'github.com/metio/kurly/workloads/redaxo/server.libsonnet';
//   kurly.list(redaxo(server='https://cms.example.com'))
//
// Serves the web app on :80 — compose an exposure onto it.
//
// DATABASE & SECRETS: the entrypoint writes the database connection into the copied
// tree and then runs the installer, so a reachable MySQL/MariaDB is a prerequisite of
// the FIRST boot, not only of serving. Coordinates travel as env; REDAXO_DB_PASSWORD
// and REDAXO_ADMIN_PASSWORD come from a provided Secret via envFrom. kurly authors no
// Secret.
//
// The entrypoint runs under `set -u` and reads every REDAXO_* variable
// unconditionally, so each one is SET here even when it is empty — an unset optional
// variable aborts the setup with an unbound-variable error before Apache ever starts.
//
// Setup copies /usr/src/redaxo into the document root, runs the installer and chowns
// the writable directories to www-data before Apache forks its workers as www-data:
// root, its capabilities and a writable image tree are relaxed deliberately.
//
// Single writer: the whole application tree, including uploaded media, lives on a
// ReadWriteOnce volume, so one replica, recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='redaxo',
  image=defaultImage,
  // /var/www/html: the application tree, the installed addons and uploaded media.
  storageSize='10Gi',
  storageClass=null,
  // The MySQL/MariaDB it installs into. The database must already exist — setup runs
  // with --db-createdb=no.
  dbHost='redaxo-db',
  database='redaxo',
  dbUser='redaxo',
  dbCharset='utf8mb4',
  // The public URL REDAXO builds links against, and the site name shown beside it.
  // Left unset, the installer keeps its own default, which points somewhere that is
  // not this installation.
  server=null,
  serverName=null,
  // Where REDAXO mails error reports.
  errorEmail=null,
  // Backend language and timezone of the installation.
  lang='en_gb',
  timezone='UTC',
  // The administrator account setup creates; its password comes from the Secret.
  adminUser='admin',
  // The Secret holding REDAXO_DB_PASSWORD and REDAXO_ADMIN_PASSWORD (kurly mints
  // none), via envFrom.
  secretName='redaxo',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
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
      REDAXO_DB_HOST: dbHost,
      REDAXO_DB_NAME: database,
      REDAXO_DB_LOGIN: dbUser,
      REDAXO_DB_CHARSET: dbCharset,
      REDAXO_LANG: lang,
      REDAXO_TIMEZONE: timezone,
      REDAXO_ADMIN_USER: adminUser,
      // Read unconditionally by the entrypoint under `set -u`: empty means "leave it
      // to the installer", unset means the setup dies before it starts.
      REDAXO_SERVER: if server == null then '' else server,
      REDAXO_SERVERNAME: if serverName == null then '' else serverName,
      REDAXO_ERROR_EMAIL: if errorEmail == null then '' else errorEmail,
    }
    + env
  )
  + kurly.envFromSecret(secretName)
  // Every variable the entrypoint reads is REDAXO_*, and a Service named after this
  // workload makes Kubernetes inject REDAXO_PORT as a tcp:// URL into the same
  // namespace of names.
  + kurly.disableServiceLinks()
  // Setup copies the application tree into the document root, runs the installer and
  // chowns redaxo/cache and redaxo/data to www-data, before Apache forks its workers
  // as www-data.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  + kurly.writableRootFilesystem()
  + kurly.store('/var/www/html', storageSize, storageClass=storageClass)
  // The first boot waits for the database, copies the tree and installs the schema
  // before Apache binds. Probe by connection: the document root redirects into the
  // backend login once setup is done.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
