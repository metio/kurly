// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// evershop — an EverShop server (an e-commerce platform: product catalogue,
// cart, checkout and an admin interface). A plain composable kurly.http workload
// on the official image, backed by an EXTERNAL PostgreSQL — the cnpg-cluster
// workload provides one — with product images and other uploaded media on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local evershop = import 'github.com/metio/kurly/workloads/evershop/server.libsonnet';
//   kurly.list(evershop())
//
// Serves the storefront and the admin interface on :3000 — compose an exposure
// onto it. The image's EXPOSE says 80, which the application never binds: the
// port comes from PORT and defaults to 3000.
//
// The server MIGRATES the schema on every start, before it listens, so a first
// boot against an empty database takes minutes — hence the startup probe rather
// than a stretched liveness delay.
//
// Single writer: uploaded media lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='evershop',
  image=defaultImage,
  // Product images and every other uploaded file, under /app/media.
  storageSize='10Gi',
  storageClass=null,
  // The PostgreSQL it connects to. The coordinates are env; the password lives
  // in the Secret.
  dbHost='evershop-db-rw',
  dbPort=5432,
  database='evershop',
  dbUser='evershop',
  // 'disable' | 'require' | 'prefer' | 'verify-ca' | 'verify-full' | 'no-verify'.
  dbSslMode='disable',
  // The Secret holding DB_PASSWORD (kurly mints none), pulled in via envFrom.
  secretName='evershop',
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.env(
    {
      PORT: '3000',
      DB_HOST: dbHost,
      DB_PORT: std.toString(dbPort),
      DB_NAME: database,
      DB_USER: dbUser,
      DB_SSLMODE: dbSslMode,
    } + env
  )
  + kurly.envFromSecret(secretName)
  // A Service named after the workload injects EVERSHOP_PORT as a tcp:// URL;
  // nothing here reads it, but the storefront renders links from the environment,
  // so the links stay out.
  + kurly.disableServiceLinks()
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // The render cache and the built entry points live beside the code in
  // /app/.evershop; a scratch there keeps the rest of the root filesystem
  // read-only.
  + kurly.scratch('/app/.evershop')
  + kurly.store('/app/media', storageSize, storageClass=storageClass)
  // Schema migrations run before the server listens, so probe by connection and
  // give the first boot room.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 60, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
