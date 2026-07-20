// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// matomo — a Matomo server (a privacy-focused, self-hosted web-analytics platform,
// the open-source Google Analytics alternative). A plain composable kurly.http
// workload on the official image, backed by an external MySQL/MariaDB, with its
// config and plugins on a PersistentVolume. Import it, point it at a database, and
// render with kurly.list:
//
//   local matomo = import 'github.com/metio/kurly/workloads/matomo/server.libsonnet';
//   kurly.list(matomo())
//
// Serves the web app and tracking API on :80 — compose an exposure onto it.
//
// DATABASE & SECRETS: Matomo needs a MySQL/MariaDB database — the mysql-cluster
// workload provides one. It reads its database coordinates from env and
// MATOMO_DATABASE_PASSWORD from a provided Secret via envFrom. kurly authors no
// Secret.
//
// The Apache + PHP image starts as root and binds :80, so this relaxes kurly's
// non-root and read-only-rootfs defaults while keeping dropped capabilities and no
// privilege escalation.
//
// Single writer: config and plugins live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='matomo',
  image='docker.io/library/matomo:5.12.0-apache',
  storageSize='5Gi',
  storageClass=null,
  dbHost='matomo-db',
  dbName='matomo',
  dbUser='matomo',
  // The Secret holding MATOMO_DATABASE_PASSWORD (kurly mints none), via envFrom.
  secretName='matomo-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    MATOMO_DATABASE_HOST: dbHost,
    MATOMO_DATABASE_USERNAME: dbUser,
    MATOMO_DATABASE_DBNAME: dbName,
    MATOMO_DATABASE_ADAPTER: 'mysql',
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
  + kurly.writableRootFilesystem()
  + kurly.store('/var/www/html', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
