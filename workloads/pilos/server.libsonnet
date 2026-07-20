// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// pilos — a PILOS server (an open-source, Laravel-based front-end for BigBlueButton,
// developed at TH Mittelhessen: room and meeting management with LDAP/OIDC support).
// A plain composable kurly.http workload on the official all-in-one image (nginx +
// php-fpm), backed by an external PostgreSQL and Redis, with its uploaded assets on a
// PersistentVolume. It reaches an existing BigBlueButton server over the network —
// kurly does not run BBB itself. Import it, point it at its backends, and render with
// kurly.list:
//
//   local pilos = import 'github.com/metio/kurly/workloads/pilos/server.libsonnet';
//   kurly.list(pilos())
//
// Serves the web app on :80 — compose an exposure onto it.
//
// BACKENDS & SECRETS: PILOS reads its database, Redis, APP_KEY and the BigBlueButton
// server list from the environment. kurly authors no Secret; provide one holding them,
// pulled in via envFrom. The defaults pair with a cnpg-cluster named pilos-db and a
// Redis.
//
// Single writer: uploaded logos and files live on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the files. The bundled nginx
// master needs root and a writable rootfs.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='pilos',
  image='docker.io/pilos/pilos:4.17.0',
  storageSize='5Gi',
  storageClass=null,
  // The Secret holding the database/Redis/APP_KEY/BBB settings (kurly mints none),
  // via envFrom.
  secretName='pilos-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.envFromSecret(secretName)
  + kurly.env(env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/var/www/html/storage/app', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
