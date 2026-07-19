// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// invoiceninja — an Invoice Ninja server (self-hosted invoicing, quotes, and
// payments). A plain composable kurly.http workload on the official image, backed
// by an external MySQL/MariaDB, with its uploads and generated PDFs on a
// PersistentVolume. Import it, point it at a database, and render with kurly.list:
//
//   local invoiceninja = import 'github.com/metio/kurly/workloads/invoiceninja/server.libsonnet';
//   kurly.list(invoiceninja(appUrl='https://invoicing.example.com'))
//
// Serves the web app and API on :80 — compose an exposure onto it.
//
// DATABASE & SECRETS: Invoice Ninja needs a MySQL/MariaDB database (kurly ships no
// MySQL recipe — bring your own, or an operator-managed one). It reads DB_HOST,
// DB_DATABASE, DB_USERNAME from env and DB_PASSWORD and APP_KEY from a provided
// Secret via envFrom. kurly authors no Secret.
//
// The nginx + PHP-FPM image starts as root and binds :80, so this relaxes kurly's
// non-root and read-only-rootfs defaults while keeping dropped capabilities and no
// privilege escalation.
//
// Single writer: uploads and PDFs live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='invoiceninja',
  image='docker.io/invoiceninja/invoiceninja:5.13.26',
  storageSize='5Gi',
  storageClass=null,
  dbHost='invoiceninja-db',
  dbName='invoiceninja',
  dbUser='invoiceninja',
  // The public URL Invoice Ninja builds links against.
  appUrl=null,
  // The Secret holding DB_PASSWORD and APP_KEY (kurly mints none), via envFrom.
  secretName='invoiceninja-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    DB_CONNECTION: 'mysql',
    DB_HOST: dbHost,
    DB_PORT: '3306',
    DB_DATABASE: dbName,
    DB_USERNAME: dbUser,
  } + (if appUrl == null then {} else { APP_URL: appUrl });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/var/www/html/storage', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
