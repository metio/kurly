// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// wordpress — a WordPress server (the world's most popular CMS and blogging
// platform). A plain composable kurly.http workload on the official image, backed by
// an external MySQL/MariaDB, with its content (themes, plugins, uploads) on a
// PersistentVolume. Import it, point it at a database, and render with kurly.list:
//
//   local wordpress = import 'github.com/metio/kurly/workloads/wordpress/server.libsonnet';
//   kurly.list(wordpress())
//
// Serves the site on :80 — compose an exposure onto it.
//
// DATABASE & SECRETS: WordPress needs a MySQL/MariaDB database (kurly ships no MySQL
// recipe — bring your own). It reads WORDPRESS_DB_HOST, WORDPRESS_DB_NAME,
// WORDPRESS_DB_USER from env and WORDPRESS_DB_PASSWORD from a provided Secret via
// envFrom. kurly authors no Secret.
//
// The Apache + PHP image starts as root and binds :80, so this relaxes kurly's
// non-root and read-only-rootfs defaults while keeping dropped capabilities and no
// privilege escalation.
//
// Single writer: the content lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='wordpress',
  image='docker.io/library/wordpress:6.9.4-php8.3-apache',
  storageSize='10Gi',
  storageClass=null,
  dbHost='wordpress-db',
  dbName='wordpress',
  dbUser='wordpress',
  // The Secret holding WORDPRESS_DB_PASSWORD (kurly mints none), via envFrom.
  secretName='wordpress-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    WORDPRESS_DB_HOST: dbHost,
    WORDPRESS_DB_NAME: dbName,
    WORDPRESS_DB_USER: dbUser,
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
