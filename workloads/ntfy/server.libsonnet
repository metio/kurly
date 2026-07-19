// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// ntfy — an ntfy server (send push notifications to your phone or desktop over
// simple HTTP). A plain composable kurly.http workload: it keeps its message cache
// and user database in SQLite on a PersistentVolume, so it needs no external
// database. Import it and render with kurly.list:
//
//   local ntfy = import 'github.com/metio/kurly/workloads/ntfy/server.libsonnet';
//   kurly.list(ntfy(baseUrl='https://ntfy.example.com'))
//
// Serves the web app and publish/subscribe API on :80 — compose an exposure onto
// it.
//
// Single writer: the SQLite cache and auth database live on a ReadWriteOnce volume,
// so one replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='ntfy',
  image='docker.io/binwiederhier/ntfy:v2.26.0',
  storageSize='1Gi',
  storageClass=null,
  // The public base URL — needed for the web app, attachments, and iOS.
  baseUrl=null,
  env={},
  resources={ requests: { cpu: '25m', memory: '32Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    NTFY_CACHE_FILE: '/var/lib/ntfy/cache.db',
    NTFY_AUTH_FILE: '/var/lib/ntfy/auth.db',
    NTFY_LISTEN_HTTP: ':80',
    NTFY_ATTACHMENT_CACHE_DIR: '/var/lib/ntfy/attachments',
  } + (if baseUrl == null then {} else { NTFY_BASE_URL: baseUrl });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.command(['serve'])
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/var/lib/ntfy', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '32Mi')
  + kurly.readinessProbe({ httpGet: { path: '/v1/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/v1/health', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
