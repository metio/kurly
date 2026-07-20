// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// baserow — a Baserow server (an open-source, no-code database and Airtable
// alternative). A plain composable kurly.http workload on the official ALL-IN-ONE
// image, which bundles the backend, the web frontend, Celery workers, and (by
// default) an embedded PostgreSQL and Redis — everything in /baserow/data on a
// PersistentVolume, so a single instance needs nothing external. Import it and render
// with kurly.list:
//
//   local baserow = import 'github.com/metio/kurly/workloads/baserow/server.libsonnet';
//   kurly.list(baserow(publicUrl='https://baserow.example.com'))
//
// Serves the web app and API on :80 — compose an exposure onto it. Point
// DATABASE_* / REDIS_* at external services through env (and a Secret) to scale past
// the embedded single instance.
//
// The all-in-one image supervises multiple processes (including the embedded
// database) and writes across the root filesystem, so this relaxes kurly's non-root
// and read-only-rootfs defaults while keeping dropped capabilities and no privilege
// escalation.
//
// Single writer: everything lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the data.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='baserow',
  image='docker.io/baserow/baserow:2.3.2',
  storageSize='10Gi',
  storageClass=null,
  // The public URL Baserow builds links against (required).
  publicUrl=null,
  // The Secret holding BASEROW_SECRET_KEY and BASEROW_JWT_SIGNING_KEY (kurly mints
  // none), via envFrom.
  secretName='baserow-secrets',
  env={},
  resources={ requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    BASEROW_DATA_DIR: '/baserow/data',
  } + (if publicUrl == null then {} else { BASEROW_PUBLIC_URL: publicUrl });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/baserow/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/api/_health/', port: 'http' }, initialDelaySeconds: 30, periodSeconds: 15, failureThreshold: 20 })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' }, initialDelaySeconds: 60 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
