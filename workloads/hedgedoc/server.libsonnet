// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// hedgedoc — a HedgeDoc server (real-time, collaborative markdown notes). A plain
// composable kurly.http workload on the official image, backed by an external
// PostgreSQL, with its uploaded files on a PersistentVolume. Import it, point it at a
// database, and render with kurly.list:
//
//   local hedgedoc = import 'github.com/metio/kurly/workloads/hedgedoc/server.libsonnet';
//   kurly.list(hedgedoc(domain='pad.example.com'))
//
// Serves the web app and API on :3000 — compose an exposure onto it.
//
// DATABASE & SECRETS: HedgeDoc reads CMD_DB_URL (with the database password embedded)
// and CMD_SESSION_SECRET from the environment. kurly authors no Secret; provide one
// holding both, pulled in via envFrom. The defaults pair with a cnpg-cluster named
// hedgedoc-db.
//
// Single writer: uploaded files live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='hedgedoc',
  image='quay.io/hedgedoc/hedgedoc:1.11.0',
  storageSize='2Gi',
  storageClass=null,
  // The public domain HedgeDoc serves at.
  domain=null,
  // The Secret holding CMD_DB_URL and CMD_SESSION_SECRET (kurly mints none), via
  // envFrom.
  secretName='hedgedoc-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    CMD_PORT: '3000',
    CMD_PROTOCOL_USESSL: 'true',
    CMD_ALLOW_ANONYMOUS: 'true',
    CMD_UPLOADS_PATH: '/hedgedoc/public/uploads',
  } + (if domain == null then {} else { CMD_DOMAIN: domain });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/hedgedoc/public/uploads', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/_health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/_health', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
