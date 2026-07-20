// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// wallabag — a wallabag server (a self-hosted read-it-later app that saves clean,
// readable copies of web pages). A plain composable kurly.http workload on the
// official image, backed by an external PostgreSQL, with its saved images on a
// PersistentVolume. Import it, point it at a database, and render with kurly.list:
//
//   local wallabag = import 'github.com/metio/kurly/workloads/wallabag/server.libsonnet';
//   kurly.list(wallabag(domain='https://read.example.com'))
//
// Serves the web app and API on :80 — compose an exposure onto it.
//
// DATABASE & SECRETS: wallabag reads its database coordinates from env (with the
// SYMFONY__ENV__ prefix) and the database password and app secret from the
// environment. The non-secret coordinates default to a cnpg-cluster named
// wallabag-db; the secrets come from a provided Secret via envFrom. kurly authors no
// Secret.
//
// The Apache + PHP image starts as root and binds :80, so this relaxes kurly's
// non-root and read-only-rootfs defaults while keeping dropped capabilities and no
// privilege escalation.
//
// Single writer: saved images live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='wallabag',
  image='docker.io/wallabag/wallabag:2.6.14',
  storageSize='5Gi',
  storageClass=null,
  dbHost='wallabag-db-rw',
  dbName='wallabag',
  dbUser='wallabag',
  // The public URL wallabag builds links against (required).
  domain=null,
  // The Secret holding SYMFONY__ENV__DATABASE_PASSWORD and SYMFONY__ENV__SECRET
  // (kurly mints none), via envFrom.
  secretName='wallabag-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    SYMFONY__ENV__DATABASE_DRIVER: 'pdo_pgsql',
    SYMFONY__ENV__DATABASE_HOST: dbHost,
    SYMFONY__ENV__DATABASE_PORT: '5432',
    SYMFONY__ENV__DATABASE_NAME: dbName,
    SYMFONY__ENV__DATABASE_USER: dbUser,
  } + (if domain == null then {} else { SYMFONY__ENV__DOMAIN_NAME: domain });

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
  + kurly.store('/var/www/wallabag/web/assets/images', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
