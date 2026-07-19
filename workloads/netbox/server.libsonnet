// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// netbox — a NetBox server (the IPAM/DCIM source of truth: IP address management,
// data-center infrastructure modelling, and a full REST/GraphQL API). A plain
// composable kurly.http workload running the community image: the web front end
// (nginx-unit + gunicorn) on :8080, its uploaded media on a PersistentVolume, and
// its database and cache external. Import it, point it at PostgreSQL and Redis,
// and render with kurly.list:
//
//   local netbox = import 'github.com/metio/kurly/workloads/netbox/server.libsonnet';
//   kurly.list(netbox(allowedHosts='netbox.example.com'))
//
// Serves the UI and API on :8080 — compose an exposure onto it.
//
// DATABASE & CACHE: NetBox needs PostgreSQL and Redis. This pairs with the
// cnpg-cluster and valkey workloads — the defaults point at a CNPG cluster named
// `netbox-db` (its `-rw` Service) and a Valkey named `netbox-cache`. NetBox uses
// two logical Redis databases on that one instance: 0 for the task queue, 1 for
// the cache.
//
// SECRETS: the image reads secrets from files under /run/secrets. This mounts one
// consumer-provided Secret there, holding `secret_key` (Django's SECRET_KEY, ≥50
// chars — sessions and stored data depend on it staying stable), `db_password`
// (the PostgreSQL password, matching the CNPG `-app` Secret), and, on first bring-
// up, `superuser_password`. kurly authors no Secret; fill it with
// kurly.externalSecret.
//
// Single writer: one PersistentVolume holds uploaded media, so this is one
// replica, recreated (never rolled) to keep two pods off the ReadWriteOnce volume.
// Background jobs (webhooks, reports, scripts) run in the companion `worker` stage.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// The workload version, stamped as app.kubernetes.io/version; the release
// pipeline overwrites version.txt with the calver.
local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='netbox',
  image='docker.io/netboxcommunity/netbox:v4.6.5',
  storageSize='2Gi',
  storageClass=null,
  dbHost='netbox-db-rw',
  dbName='netbox',
  dbUser='netbox',
  redisHost='netbox-cache',
  // The Secret the image reads secret_key / db_password / superuser_password from,
  // mounted at /run/secrets. The consumer provides it; kurly mints none.
  secretName='netbox-secrets',
  // Space-separated hostnames NetBox will answer for (Django ALLOWED_HOSTS). '*'
  // accepts any Host header — fine behind a trusted ingress, tighten in the open.
  allowedHosts='*',
  // The initial superuser created on first start (its password comes from the
  // superuser_password key of the Secret). Set skipSuperuser once bootstrapped.
  superuserName='admin',
  superuserEmail='admin@example.com',
  skipSuperuser=false,
  // Extra environment (SKIP_STARTUP_SCRIPTS, EMAIL_*, CORS_*, …), merged over the
  // below. Anything sensitive belongs in the mounted Secret, not a literal here.
  env={},
  resources={ requests: { cpu: '300m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    DB_HOST: dbHost,
    DB_NAME: dbName,
    DB_USER: dbUser,
    DB_PORT: '5432',
    REDIS_HOST: redisHost,
    REDIS_PORT: '6379',
    REDIS_DATABASE: '0',
    REDIS_CACHE_HOST: redisHost,
    REDIS_CACHE_PORT: '6379',
    REDIS_CACHE_DATABASE: '1',
    ALLOWED_HOSTS: allowedHosts,
    SUPERUSER_NAME: superuserName,
    SUPERUSER_EMAIL: superuserEmail,
    SKIP_SUPERUSER: (if skipSuperuser then 'true' else 'false'),
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env(baseEnv + env)
  // The community image runs as uid 1000; pin it and its fsGroup so the media
  // volume is writable and the restricted posture admits the pod.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/opt/netbox/netbox/media', storageSize, storageClass=storageClass)
  // nginx-unit keeps its runtime state and control socket under /opt/unit and both
  // NetBox and unit write scratch files to /tmp; back them with emptyDirs so the
  // root filesystem stays read-only.
  + kurly.scratch('/opt/unit', '128Mi')
  + kurly.scratch('/tmp', '256Mi')
  + kurly.secretMount(secretName, '/run/secrets')
  // Startup runs database migrations before unit begins serving, so gate readiness
  // on the login page and keep liveness a plain socket check that won't restart a
  // pod still catching up on a long migration.
  + kurly.readinessProbe({ httpGet: { path: '/login/', port: 'http' }, initialDelaySeconds: 30, periodSeconds: 15, failureThreshold: 20 })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' }, initialDelaySeconds: 60, periodSeconds: 30 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
