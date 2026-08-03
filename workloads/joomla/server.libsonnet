// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// joomla — a A Joomla server (a popular self-hosted CMS for building websites and online applications (backed by MySQL)). A plain composable kurly.http workload on the official image,
// backed by an external database, with its data on a PersistentVolume (the image populates it
// on first run). Import it, point it at a database, and render with kurly.list:
//
//   local joomla = import 'github.com/metio/kurly/workloads/joomla/server.libsonnet';
//   kurly.list(joomla())
//
// Serves the web app on :80 — compose an exposure onto it.
//
// DATABASE & SECRETS: it reads its database connection from the environment. kurly authors no
// Secret; provide one holding the DB credentials, via envFrom.
//
// Single writer: the data lives on a ReadWriteOnce volume, so one replica, recreated. The
// Apache master runs as root then serves as www-data.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');
function(
  name='joomla',
  image=defaultImage,
  storageSize='10Gi',
  storageClass=null,
  // The MySQL/MariaDB it stores the site in. The password comes from the Secret.
  dbHost='joomla-db',
  dbName='joomla',
  dbUser='joomla',
  dbType='mysqli',
  secretName='joomla',
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
  + kurly.envFromSecret(secretName)
  + kurly.env({
    JOOMLA_DB_HOST: dbHost,
    JOOMLA_DB_NAME: dbName,
    JOOMLA_DB_USER: dbUser,
    JOOMLA_DB_TYPE: dbType,
  } + env)
  + kurly.rootUser()
  // Writes under /var/run/apache2; a scratch there keeps the rest of the root filesystem read-only.
  + kurly.scratch('/var/run/apache2')
  // Writes under /tmp; a scratch there keeps the rest of the root filesystem read-only.
  + kurly.scratch('/tmp')
  // The entrypoint unpacks Joomla onto the volume and hands it to the web user.
  // Everything is dropped and these are granted back by name — the
  // smallest set this image was observed to boot with.
  + kurly.addCapabilities(['CHOWN', 'SETGID', 'SETUID'])
  + kurly.store('/var/www/html', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
