// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// safebucket — a Safebucket server (file sharing where the bytes never touch the
// server: the API mints presigned URLs and the browser uploads to and downloads
// from S3-compatible storage directly). A composable kurly.http workload backed by
// an EXTERNAL PostgreSQL — the cnpg-cluster workload provides one — and an
// EXTERNAL S3 bucket, which seaweedfs or garage provides. Import it and render
// with kurly.list:
//
//   local safebucket = import 'github.com/metio/kurly/workloads/safebucket/server.libsonnet';
//   kurly.list(safebucket())
//
// Serves the API and the bundled web app on :8080 — compose an exposure onto it.
//
// Stateless: metadata in PostgreSQL, objects in the bucket. The filesystem
// notifier and activity log write under /app/data, which is an emptyDir here and
// therefore goes with the pod — point ACTIVITY__TYPE at a Loki and NOTIFIER__TYPE
// at an SMTP server to keep either beyond a restart.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='safebucket',
  image=defaultImage,
  replicas=1,
  // The URLs the BROWSER reaches, not in-cluster Services: they end up in issued
  // links, cookies and the CORS allow-list, so a wrong value produces a UI that
  // loads and an upload that is refused.
  apiUrl='https://safebucket.example.com',
  webUrl='https://safebucket.example.com',
  allowedOrigins='https://safebucket.example.com',
  // The first account, created on start. Its password lives in the Secret.
  adminEmail='admin@example.com',
  // The PostgreSQL it connects to. The non-secret coordinates are env; the
  // password lives in the Secret.
  dbHost='safebucket-db-rw',
  dbPort=5432,
  database='safebucket',
  dbUser='safebucket',
  dbSslMode='require',
  // The S3-compatible bucket. `s3Endpoint` is host:port as the SERVER reaches it
  // (no scheme — the client takes TLS from s3UseTls); `s3ExternalEndpoint` is the
  // absolute URL the BROWSER reaches, because presigned URLs are signed for it and
  // a cluster-internal address is unreachable from a laptop. The bucket must exist
  // and must allow CORS from webUrl: Safebucket refuses to start without it.
  s3Endpoint='seaweedfs-s3:8333',
  s3ExternalEndpoint='https://s3.example.com',
  s3Bucket='safebucket',
  s3Region='us-east-1',
  s3UseTls=false,
  // The Secret holding APP__TOKEN_SECRET, APP__MFA_ENCRYPTION_KEY,
  // APP__ADMIN_PASSWORD, DATABASE__POSTGRES__PASSWORD, STORAGE__S3__ACCESS_KEY and
  // STORAGE__S3__SECRET_KEY. None of them has a default: the server refuses to
  // start until every one is set.
  secretName='safebucket',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env(
    {
      APP__PORT: '8080',
      APP__PROFILE: 'default',
      APP__LOG_LEVEL: 'info',
      APP__API_URL: apiUrl,
      APP__WEB_URL: webUrl,
      APP__ALLOWED_ORIGINS: allowedOrigins,
      APP__ADMIN_EMAIL: adminEmail,
      APP__STATIC_FILES__ENABLED: 'true',
      DATABASE__TYPE: 'postgres',
      DATABASE__POSTGRES__HOST: dbHost,
      DATABASE__POSTGRES__PORT: std.toString(dbPort),
      DATABASE__POSTGRES__NAME: database,
      DATABASE__POSTGRES__USER: dbUser,
      DATABASE__POSTGRES__SSLMODE: dbSslMode,
      // In-process cache and event bus: a single replica needs neither a Redis nor
      // a NATS, and both are swappable by setting CACHE__TYPE / EVENTS__TYPE.
      CACHE__TYPE: 'memory',
      EVENTS__TYPE: 'memory',
      EVENTS__QUEUES__NOTIFICATIONS__NAME: 'notifications',
      EVENTS__QUEUES__BUCKET_EVENTS__NAME: 'bucket-events',
      EVENTS__QUEUES__OBJECT_DELETION__NAME: 'object-deletion',
      NOTIFIER__TYPE: 'filesystem',
      NOTIFIER__FILESYSTEM__DIRECTORY: '/app/data/notifications',
      ACTIVITY__TYPE: 'filesystem',
      ACTIVITY__FILESYSTEM__DIRECTORY: '/app/data/activity',
      STORAGE__TYPE: 's3',
      STORAGE__S3__BUCKET_NAME: s3Bucket,
      STORAGE__S3__ENDPOINT: s3Endpoint,
      STORAGE__S3__EXTERNAL_ENDPOINT: s3ExternalEndpoint,
      STORAGE__S3__REGION: s3Region,
      STORAGE__S3__USE_TLS: if s3UseTls then 'true' else 'false',
      // Path-style addressing, which every self-hosted S3 implementation needs and
      // virtual-host style breaks against.
      STORAGE__S3__FORCE_PATH_STYLE: 'true',
    } + env
  )
  + kurly.envFromSecret(secretName)
  // The notifier and the activity log write beside the binary in the image's own
  // tree, so that one path is writable and the root filesystem stays read-only.
  + kurly.scratch('/app/data')
  // A Service named safebucket would otherwise inject SAFEBUCKET_PORT=tcp://…, and
  // APP__PORT is read from the environment.
  + kurly.disableServiceLinks()
  // There is no health endpoint, so probe by connection: every path either serves
  // the single-page app or answers 401.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 30, periodSeconds: 5 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
