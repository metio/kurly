// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// kyoo api — the API of Kyoo, a media browser and streaming server for films and
// television. A plain composable kurly.http workload on the official image,
// backed by an external PostgreSQL, keeping the artwork it downloads on a
// PersistentVolume at /images. Import it, point it at its database, and render
// with kurly.list:
//
//   local kyoo = import 'github.com/metio/kurly/workloads/kyoo/server.libsonnet';
//   kurly.list(kyoo(publicUrl='https://kyoo.example.com'))
//
// Serves on :3567 — compose an exposure onto it.
//
// BACKENDS & SECRETS: the connection settings are plain parameters (PGHOST,
// PGDATABASE, PGUSER); the password comes from `secretName` as PGPASSWORD via
// envFrom, and kurly authors no Secret. The defaults pair with a cnpg-cluster
// named kyoo-db. The API creates its own `kyoo` schema and needs the pg_trgm
// extension, which a stock PostgreSQL ships.
//
// This stage carries the API alone. Kyoo's front, auth and transcoder services
// are separate images; the API validates the JWTs the auth service issues, so
// `authServer` points at it and `publicUrl` must be the issuer it stamps.
//
// Single writer: the artwork lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='kyoo',
  image=defaultImage,
  storageSize='10Gi',
  storageClass=null,
  // The public URL, which is also the issuer the auth service stamps into its JWTs.
  publicUrl=null,
  // The Kyoo auth service, whose JWKS the API fetches to verify those JWTs.
  authServer='http://kyoo-auth:4568',
  dbHost='kyoo-db-rw',
  database='kyoo',
  dbUser='kyoo',
  // The Secret holding PGPASSWORD (kurly mints none), via envFrom.
  secretName='kyoo',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local issuer = if publicUrl == null then {} else { JWT_ISSUER: publicUrl };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3567)
  + kurly.servicePort(3567)
  + kurly.envFromSecret(secretName)
  + kurly.env(issuer {
    PGHOST: dbHost,
    PGDATABASE: database,
    PGUSER: dbUser,
    AUTH_SERVER: authServer,
    IMAGES_PATH: '/images',
  } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // The compiled Bun binary unpacks its native modules under a writable temporary
  // directory; a scratch there keeps the rest of the root filesystem read-only.
  + kurly.scratch('/tmp')
  + kurly.store('/images', storageSize, storageClass=storageClass)
  // The Service is named after the app, so the Service-link environment would
  // define KYOO_PORT as a tcp:// URL.
  + kurly.disableServiceLinks()
  // The first start runs the database migrations, which outlast a liveness delay.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 30 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
