// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// twenty — a Twenty server (a modern, open-source CRM). The web/API front end, a
// kurly.http workload on the official image, backed by an external PostgreSQL and
// Redis. It needs the companion `worker` stage for background jobs. Import both and
// render with kurly.list:
//
//   local twenty = import 'github.com/metio/kurly/workloads/twenty/server.libsonnet';
//   kurly.list(twenty(serverUrl='https://crm.example.com'))
//
// Serves the app and API on :3000 — compose an exposure onto it.
//
// DATABASE, CACHE & SECRETS: Twenty reads REDIS_URL and its server URL from env,
// and PG_DATABASE_URL (with the database password embedded) and APP_SECRET from a
// provided Secret via envFrom. The defaults pair with a cnpg-cluster named
// twenty-db and a valkey named twenty-cache. kurly authors no Secret.
//
// Single writer: with local file storage, uploads live on a ReadWriteOnce volume,
// so one replica, recreated. Move STORAGE_TYPE to S3 (the seaweedfs workload) to
// scale the front end horizontally.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='twenty',
  image='docker.io/twentycrm/twenty:v2.22.0',
  storageSize='5Gi',
  storageClass=null,
  redisHost='twenty-cache',
  // The public URL Twenty serves at.
  serverUrl=null,
  // The Secret holding PG_DATABASE_URL and APP_SECRET (kurly mints none), via
  // envFrom.
  secretName='twenty-secrets',
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    REDIS_URL: 'redis://' + redisHost + ':6379',
    STORAGE_TYPE: 'local',
    STORAGE_LOCAL_PATH: '.local-storage',
  } + (if serverUrl == null then {} else { SERVER_URL: serverUrl });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/app/packages/twenty-server/.local-storage', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/healthz', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
