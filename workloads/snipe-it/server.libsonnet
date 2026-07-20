// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// snipe-it — a Snipe-IT server (a free, open-source IT asset and license management
// system). A plain composable kurly.http workload on the official image, backed by an
// external MySQL/MariaDB, with its uploads on a PersistentVolume. Import it, point it
// at a database, and render with kurly.list:
//
//   local snipeit = import 'github.com/metio/kurly/workloads/snipe-it/server.libsonnet';
//   kurly.list(snipeit(appUrl='https://assets.example.com'))
//
// Serves the web app and API on :80 — compose an exposure onto it.
//
// DATABASE & SECRETS: Snipe-IT needs a MySQL/MariaDB database — the mysql-cluster
// workload provides one. It reads its database coordinates from env and DB_PASSWORD
// and APP_KEY from a provided Secret via envFrom. kurly authors no Secret.
//
// The Apache + PHP image starts as root and binds :80, so this relaxes kurly's
// non-root and read-only-rootfs defaults while keeping dropped capabilities and no
// privilege escalation.
//
// Single writer: uploads live on a ReadWriteOnce volume, so one replica, recreated
// (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='snipe-it',
  image='docker.io/snipe/snipe-it:v8.6.3',
  storageSize='5Gi',
  storageClass=null,
  dbHost='snipe-it-db',
  dbName='snipeit',
  dbUser='snipeit',
  // The public URL Snipe-IT builds links against (required).
  appUrl=null,
  // The Secret holding DB_PASSWORD and APP_KEY (kurly mints none), via envFrom.
  secretName='snipe-it-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    MYSQL_PORT_3306_TCP_ADDR: dbHost,
    MYSQL_PORT_3306_TCP_PORT: '3306',
    MYSQL_DATABASE: dbName,
    MYSQL_USER: dbUser,
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
  + kurly.store('/var/lib/snipeit', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
