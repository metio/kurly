// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// nocodb — a NocoDB server (an open-source Airtable alternative that turns any SQL
// database into a smart spreadsheet). A plain composable kurly.http workload on the
// official image, backed by an external PostgreSQL for its metadata, with attachments
// on a PersistentVolume. Import it, point it at a database, and render with
// kurly.list:
//
//   local nocodb = import 'github.com/metio/kurly/workloads/nocodb/server.libsonnet';
//   kurly.list(nocodb(publicUrl='https://nocodb.example.com'))
//
// Serves the web app and API on :8080 — compose an exposure onto it.
//
// DATABASE & SECRETS: NocoDB reads NC_DB (a connection string with the database
// password) and NC_AUTH_JWT_SECRET from the environment. kurly authors no Secret;
// provide one holding both, pulled in via envFrom. Point NC_DB at a cnpg-cluster.
//
// Single writer: local attachments live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files. Move attachments to S3
// (the seaweedfs workload) to scale out.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='nocodb',
  image='docker.io/nocodb/nocodb:2026.07.0',
  storageSize='5Gi',
  storageClass=null,
  // The public URL NocoDB builds links against.
  publicUrl=null,
  // The Secret holding NC_DB and NC_AUTH_JWT_SECRET (kurly mints none), via envFrom.
  secretName='nocodb-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    NC_TOOL_DIR: '/usr/app/data',
  } + (if publicUrl == null then {} else { NC_PUBLIC_URL: publicUrl });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/usr/app/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ httpGet: { path: '/api/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/health', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
