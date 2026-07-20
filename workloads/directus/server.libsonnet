// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// directus — a Directus server (an open-source headless CMS and data platform over
// your SQL database). A plain composable kurly.http workload on the official image,
// backed by an external PostgreSQL, with its uploads on a PersistentVolume. Import
// it, point it at a database, and render with kurly.list:
//
//   local directus = import 'github.com/metio/kurly/workloads/directus/server.libsonnet';
//   kurly.list(directus(publicUrl='https://cms.example.com'))
//
// Serves the admin app and API on :8055 — compose an exposure onto it.
//
// DATABASE & SECRETS: Directus reads its database coordinates from env, and
// DB_PASSWORD, KEY, SECRET, and the first-run ADMIN_PASSWORD from the environment
// too. The non-secret coordinates default to a cnpg-cluster named directus-db; the
// secrets come from a provided Secret via envFrom. kurly authors no Secret.
//
// Single writer: uploaded files live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='directus',
  image='docker.io/directus/directus:12.1.1',
  storageSize='10Gi',
  storageClass=null,
  dbHost='directus-db-rw',
  dbName='directus',
  dbUser='directus',
  publicUrl=null,
  adminEmail='admin@example.com',
  // The Secret holding DB_PASSWORD, KEY, SECRET, and ADMIN_PASSWORD (kurly mints
  // none), via envFrom.
  secretName='directus-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    DB_CLIENT: 'pg',
    DB_HOST: dbHost,
    DB_PORT: '5432',
    DB_DATABASE: dbName,
    DB_USER: dbUser,
    ADMIN_EMAIL: adminEmail,
    STORAGE_LOCATIONS: 'local',
    STORAGE_LOCAL_ROOT: '/directus/uploads',
  } + (if publicUrl == null then {} else { PUBLIC_URL: publicUrl });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8055)
  + kurly.servicePort(8055)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/directus/uploads', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ httpGet: { path: '/server/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/server/health', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
