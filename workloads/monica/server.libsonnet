// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// monica — a Monica server (a self-hosted personal relationship manager: keep track
// of your interactions with the people who matter). A plain composable kurly.http
// workload on the official image, backed by an external MySQL/MariaDB, with its
// uploads on a PersistentVolume. Import it, point it at a database, and render with
// kurly.list:
//
//   local monica = import 'github.com/metio/kurly/workloads/monica/server.libsonnet';
//   kurly.list(monica(appUrl='https://monica.example.com'))
//
// Serves the web app on :80 — compose an exposure onto it.
//
// DATABASE & SECRETS: Monica needs a MySQL/MariaDB database — the mysql-cluster
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
  name='monica',
  image='docker.io/library/monica:4.1.2-apache',
  storageSize='5Gi',
  storageClass=null,
  dbHost='monica-db',
  dbName='monica',
  dbUser='monica',
  // The public URL Monica builds links against (required).
  appUrl=null,
  // The Secret holding DB_PASSWORD and APP_KEY (kurly mints none), via envFrom.
  secretName='monica-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
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
