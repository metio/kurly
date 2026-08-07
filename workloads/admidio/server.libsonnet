// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// admidio — an Admidio server (member management for clubs and organisations: people,
// the roles they hold, events and the mailings that go with them). A composable
// kurly.http workload backed by an EXTERNAL MySQL/MariaDB or PostgreSQL — the
// mysql-cluster and cnpg-cluster workloads provide one — with its generated
// configuration and uploaded files on a PersistentVolume. Import it and render with
// kurly.list:
//
//   local admidio = import 'github.com/metio/kurly/workloads/admidio/server.libsonnet';
//   kurly.list(admidio())
//
// Serves the web app on :8080 — compose an exposure onto it.
//
// DATABASE & SECRETS: dbType selects which engine the generated config.php speaks
// ('mysql' or 'pgsql'); the coordinates are env and ADMIDIO_DB_PASSWORD comes from a
// provided Secret via envFrom. kurly authors no Secret.
//
// The entrypoint provisions the application tree, chowns it to www-data, rewrites the
// Apache port configuration and starts cron and postfix before Apache drops to
// www-data — all of which needs root, capabilities and a writable image tree.
//
// Single writer: configuration and uploads on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='admidio',
  image=defaultImage,
  // adm_my_files: the generated config.php, uploaded documents and photos.
  storageSize='10Gi',
  storageClass=null,
  // The database it connects to. 'mysql' also covers MariaDB; 'pgsql' is PostgreSQL.
  dbType='mysql',
  dbHost='admidio-db',
  dbPort=3306,
  database='admidio',
  dbUser='admidio',
  // The public URL Admidio writes into its configuration and builds links against.
  // Absent leaves the placeholder from the shipped example configuration, which
  // sends every generated link somewhere that is not this installation.
  rootPath=null,
  // The organisation short name the first installation is created for.
  organisation=null,
  // The SMTP relay postfix hands outgoing mail to. Without it mail is queued and
  // never leaves the pod.
  mailRelayHost=null,
  // The Secret holding ADMIDIO_DB_PASSWORD (kurly mints none), via envFrom.
  secretName='admidio',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env(
    {
      ADMIDIO_DB_TYPE: dbType,
      ADMIDIO_DB_HOST: dbHost,
      ADMIDIO_DB_PORT: std.toString(dbPort),
      ADMIDIO_DB_NAME: database,
      ADMIDIO_DB_USER: dbUser,
    }
    + (if rootPath == null then {} else { ADMIDIO_ROOT_PATH: rootPath })
    + (if organisation == null then {} else { ADMIDIO_ORGANISATION: organisation })
    + (if mailRelayHost == null then {} else { ADMIDIO_MAIL_RELAYHOST: mailRelayHost })
    + env
  )
  + kurly.envFromSecret(secretName)
  // Every variable the entrypoint reads is ADMIDIO_*, and a Service named after this
  // workload makes Kubernetes inject ADMIDIO_PORT as a tcp:// URL into the same
  // namespace of names.
  + kurly.disableServiceLinks()
  // The entrypoint copies the provisioning tree into the document root, chowns it to
  // www-data, edits /etc/apache2 and starts cron and postfix, before Apache forks its
  // workers as www-data.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  + kurly.writableRootFilesystem()
  + kurly.store('/opt/app-root/src/adm_my_files', storageSize, storageClass=storageClass)
  // Apache answers on :8080 as soon as it is up, but the entrypoint provisions the
  // whole application tree first. Probe by connection: the document root redirects
  // into the installation wizard until an administrator has walked it.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
