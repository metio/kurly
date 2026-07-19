// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// wger — a wger server (a self-hosted workout, nutrition, and body-weight
// manager). A plain composable kurly.http workload on the official all-in-one
// image, backed by an external PostgreSQL and Redis, with its uploaded media on a
// PersistentVolume. Import it, point it at a database and cache, and render with
// kurly.list:
//
//   local wger = import 'github.com/metio/kurly/workloads/wger/server.libsonnet';
//   kurly.list(wger(siteUrl='https://wger.example.com'))
//
// Serves the web app on :80 — compose an exposure onto it.
//
// DATABASE, CACHE & SECRETS: wger reads its database and cache coordinates and its
// SECRET_KEY from the environment. The non-secret coordinates default to a
// cnpg-cluster named wger-db and a valkey named wger-cache; the sensitive values
// (DJANGO_DB_PASSWORD, SECRET_KEY) come from a provided Secret via envFrom. kurly
// authors no Secret.
//
// The all-in-one image runs nginx + uWSGI + Celery and binds :80, so this relaxes
// kurly's non-root and read-only-rootfs defaults while keeping dropped
// capabilities and no privilege escalation.
//
// Single writer: uploaded media lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='wger',
  image='docker.io/wger/server:2.6.0',
  storageSize='2Gi',
  storageClass=null,
  dbHost='wger-db-rw',
  dbName='wger',
  dbUser='wger',
  redisHost='wger-cache',
  // The public URL wger builds links against.
  siteUrl=null,
  // The Secret holding DJANGO_DB_PASSWORD and SECRET_KEY (kurly mints none),
  // via envFrom.
  secretName='wger-secrets',
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    DJANGO_DB_ENGINE: 'django.db.backends.postgresql',
    DJANGO_DB_DATABASE: dbName,
    DJANGO_DB_USER: dbUser,
    DJANGO_DB_HOST: dbHost,
    DJANGO_DB_PORT: '5432',
    DJANGO_CACHE_BACKEND: 'django_redis.cache.RedisCache',
    DJANGO_CACHE_LOCATION: 'redis://' + redisHost + ':6379/1',
    DJANGO_CACHE_CLIENT_CLASS: 'django_redis.client.DefaultClient',
  } + (if siteUrl == null then {} else { SITE_URL: siteUrl });

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
  + kurly.store('/home/wger/media', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
