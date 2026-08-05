// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// warracker — a Warracker server (keeps track of product warranties: what you
// bought, when the cover expires, and the receipts and manuals that go with it,
// with reminders before each one lapses). A composable kurly.http workload backed
// by an EXTERNAL PostgreSQL — the cnpg-cluster workload provides one — with
// uploaded documents on a PersistentVolume. Import it and render with kurly.list:
//
//   local warracker = import 'github.com/metio/kurly/workloads/warracker/server.libsonnet';
//   kurly.list(warracker())
//
// Serves the web app on :80 — compose an exposure onto it.
//
// Single writer: uploaded documents on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='warracker',
  image=defaultImage,
  // Receipts, manuals and photos.
  storageSize='10Gi',
  storageClass=null,
  // The PostgreSQL it connects to. The non-secret coordinates are env; the
  // passwords live in the Secret.
  dbHost='warracker-db-rw',
  dbPort=5432,
  database='warracker',
  dbUser='warracker',
  // The Secret holding DB_PASSWORD, DB_ADMIN_PASSWORD and SECRET_KEY. Every one of
  // them has a published default in the project's own compose file — including the
  // Flask SECRET_KEY that signs sessions — so supplying them is not hardening, it
  // is the difference between having accounts and not.
  secretName='warracker',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env(
    {
      DB_HOST: dbHost,
      DB_PORT: std.toString(dbPort),
      DB_NAME: database,
      DB_USER: dbUser,
      DB_ADMIN_USER: dbUser,
    } + env
  )
  + kurly.envFromSecret(secretName)
  // supervisord runs nginx and the Flask application together and drops privileges
  // to their accounts, which it can only do from root; nginx also binds :80.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  // nginx and supervisord keep their pid, logs and temporary bodies inside the
  // image's own tree.
  + kurly.writableRootFilesystem()
  + kurly.store('/data/uploads', storageSize, storageClass=storageClass)
  + kurly.startupProbe({ httpGet: { path: '/', port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
