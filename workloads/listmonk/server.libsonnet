// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// listmonk — a listmonk server (a self-hosted newsletter and mailing-list manager).
// A plain composable kurly.http workload on the official image, backed by an
// external PostgreSQL, with its uploaded media on a PersistentVolume. Import it,
// point it at a database, and render with kurly.list:
//
//   local listmonk = import 'github.com/metio/kurly/workloads/listmonk/server.libsonnet';
//   kurly.list(listmonk())
//
// Serves the admin UI and API on :9000 — compose an exposure onto it.
//
// DATABASE & SECRETS: listmonk reads its database and admin coordinates from the
// environment (LISTMONK_db__* and LISTMONK_app__admin_*). The non-secret coordinates
// default to a cnpg-cluster named listmonk-db; the passwords come from a provided
// Secret via envFrom. kurly authors no Secret. Run the one-time schema install with
// `./listmonk --install` (or --upgrade) against the database before first use.
//
// Single writer: uploaded media lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='listmonk',
  image='docker.io/listmonk/listmonk:v6.2.0',
  storageSize='2Gi',
  storageClass=null,
  dbHost='listmonk-db-rw',
  dbName='listmonk',
  dbUser='listmonk',
  adminUser='admin',
  // The Secret holding LISTMONK_db__password and LISTMONK_app__admin_password
  // (kurly mints none), via envFrom.
  secretName='listmonk-secrets',
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    LISTMONK_db__host: dbHost,
    LISTMONK_db__port: '5432',
    LISTMONK_db__user: dbUser,
    LISTMONK_db__database: dbName,
    LISTMONK_db__ssl_mode: 'disable',
    LISTMONK_app__address: '0.0.0.0:9000',
    LISTMONK_app__admin_username: adminUser,
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(9000)
  + kurly.servicePort(9000)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/listmonk/uploads', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/api/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/health', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
