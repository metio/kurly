// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mastodon (web) — the Mastodon web/API server: the Rails app of Mastodon, the leading
// self-hosted ActivityPub/Fediverse microblogging platform. Mastodon runs as THREE workloads —
// this web server, a `streaming` server for real-time timelines, and a `sidekiq` background
// worker — backed by an external PostgreSQL and Redis, with media in S3-compatible object
// storage. Import it, point it at its backends, and render with kurly.list:
//
//   local web = import 'github.com/metio/kurly/workloads/mastodon/web.libsonnet';
//   kurly.list(web(localDomain='social.example.com'))
//
// Serves the web app and API on :3000 — compose an exposure onto it.
//
// LOCAL DOMAIN IS PERMANENT: LOCAL_DOMAIN is baked into every account's @handle and cannot be
// changed later, so set it deliberately.
//
// BACKENDS & SECRETS: Mastodon reads its PostgreSQL and Redis connection, the SECRET_KEY_BASE,
// OTP_SECRET, the VAPID keys, and the S3 settings from the environment. kurly authors no Secret;
// provide one holding them, via envFrom. All three stages share it. Pairs with a cnpg-cluster
// named mastodon-db, a Redis and an S3 bucket (e.g. seaweedfs).
//
// Stateless (with S3 media): a plain rolling Deployment.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './web.image', '\n');
function(
  name='mastodon',
  image=defaultImage,
  replicas=2,
  localDomain=null,
  // The PostgreSQL and Redis it stores everything in; the passwords come from the
  // Secret.
  dbHost='mastodon-db-rw',
  dbPort=5432,
  dbName='mastodon',
  dbUser='mastodon',
  redisHost='mastodon-cache-headless',
  redisPort=6379,
  secretName='mastodon',
  env={},
  resources={ requests: { cpu: '250m', memory: '768Mi' }, limits: { memory: '1536Mi' } },
  labels={},
  annotations={},
)
  local baseEnv =
    {
      RAILS_ENV: 'production',
      DB_HOST: dbHost,
      DB_PORT: std.toString(dbPort),
      DB_NAME: dbName,
      DB_USER: dbUser,
      REDIS_HOST: redisHost,
      REDIS_PORT: std.toString(redisPort),
    }
    + (if localDomain == null then {} else { LOCAL_DOMAIN: localDomain });
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.command(['bundle', 'exec', 'puma', '-C', 'config/puma.rb'])
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(991, gid=991, fsGroup=991)
  + kurly.writableRootFilesystem()
  + kurly.scratch('/mastodon/tmp', '256Mi')
  // Mastodon needs its schema in place before the server (or a worker) can load
  // the application; db:prepare creates it on an empty database and migrates an
  // existing one, so it runs before every start.
  + kurly.initContainer({
    name: 'migrate',
    image: image,
    command: ['bundle', 'exec', 'rails', 'db:prepare'],
    envFrom: [{ secretRef: { name: secretName } }],
    env: [{ name: k, value: baseEnv[k] } for k in std.objectFields(baseEnv)],
  })
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
