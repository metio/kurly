// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// teable — a Teable server (a self-hosted, no-code database built on PostgreSQL that presents as a
// spreadsheet — an Airtable alternative). A plain composable kurly.http workload on the official
// image, backed by an external PostgreSQL (and Redis for realtime/caching). Import it, point it at
// its backends, and render with kurly.list:
//
//   local teable = import 'github.com/metio/kurly/workloads/teable/server.libsonnet';
//   kurly.list(teable(publicOrigin='https://teable.example.com'))
//
// Serves the web app on :3000 — compose an exposure onto it.
//
// BACKENDS & SECRETS: Teable reads PRISMA_DATABASE_URL, BACKEND_CACHE_REDIS_URI, SECRET_KEY and
// its mail/storage settings from the environment. kurly authors no Secret; provide one holding
// them, via envFrom. The defaults pair with a cnpg-cluster named teable-db and a Redis. Uploaded
// attachments go to S3 when the storage settings point at a bucket (otherwise local disk — add a
// store then).
//
// Stateless with S3 storage: a plain rolling Deployment.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');
function(
  name='teable',
  image=defaultImage,
  replicas=2,
  publicOrigin=null,
  secretName='teable',
  env={},
  resources={ requests: { cpu: '250m', memory: '768Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = if publicOrigin == null then {} else { PUBLIC_ORIGIN: publicOrigin };
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.envFromSecret(secretName)
  // corepack caches into the account's home, which the image does not give its
  // unprivileged user — point it at the writable scratch instead.
  + kurly.env({ HOME: '/tmp' } + baseEnv + env)
  // The image's own nodejs account owns the asset cache it writes on start.
  + kurly.runAs(1001, gid=1001, fsGroup=1001)
  + kurly.scratch('/tmp', '128Mi')
  // It opens a cache database under .assets, relative to its workdir /app —
  // "EROFS: read-only file system, open '.assets/.cache.db'". The image ships that
  // directory empty, so a scratch there hides nothing.
  + kurly.scratch('/app/.assets', '128Mi')
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  // Teable runs its Prisma migrations and builds its asset cache before it listens
  // on 3000, which on a first start against an empty database takes minutes. The
  // liveness probe otherwise reaches its threshold during that work and restarts
  // the container, which starts the same slow work again and never completes it.
  // 10 minutes of grace, after which liveness resumes at its own cadence.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 120, periodSeconds: 5 })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
