// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// endurain — an Endurain server (a self-hosted fitness and training-activity
// tracker). A plain composable kurly.http workload backed by an external
// PostgreSQL and Redis, with its uploaded activity files and photos on a
// PersistentVolume. Import it, point it at a database and cache, and render with
// kurly.list:
//
//   local endurain = import 'github.com/metio/kurly/workloads/endurain/server.libsonnet';
//   kurly.list(endurain(endurainHost='https://fitness.example.com'))
//
// Serves the web app and API on :8080 — compose an exposure onto it.
//
// DATABASE, CACHE & SECRETS: Endurain reads its database and cache coordinates and
// its SECRET_KEY from the environment. The non-secret coordinates default to a
// cnpg-cluster named endurain-db and a valkey named endurain-cache; the sensitive
// values (DB_PASSWORD, SECRET_KEY) come from a provided Secret via envFrom. kurly
// authors no Secret.
//
// Single writer: uploaded files and photos live on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='endurain',
  image='ghcr.io/joaovitoriasilva/endurain:0.17.7',
  storageSize='5Gi',
  storageClass=null,
  dbHost='endurain-db-rw',
  dbName='endurain',
  dbUser='endurain',
  redisHost='endurain-cache',
  // The public URL the app builds links against.
  endurainHost=null,
  // The Secret holding DB_PASSWORD and SECRET_KEY (kurly mints none), via envFrom.
  secretName='endurain-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    DB_TYPE: 'postgres',
    DB_HOST: dbHost,
    DB_PORT: '5432',
    DB_USER: dbUser,
    DB_DATABASE: dbName,
    REDIS_HOST: redisHost,
    REDIS_PORT: '6379',
  } + (if endurainHost == null then {} else { ENDURAIN_HOST: endurainHost });

  // Endurain keeps two upload trees under its app directory; surface the second as
  // a subpath of the same volume so both persist without hiding the app code.
  local filesMount = {
    deployment+: { spec+: { template+: { spec+: {
      containers: [
        container { volumeMounts+: [{ name: 'store', mountPath: '/app/backend/app/files', subPath: 'files' }] }
        for container in super.containers
      ],
    } } } },
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/app/backend/app/user_images', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + filesMount
