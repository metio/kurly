// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// jotty — a jotty server (notes and checklists kept as plain Markdown and JSON
// files, with no database anywhere). A plain composable kurly.http workload:
// everything it owns lives on PersistentVolumes. Import it and render with
// kurly.list:
//
//   local jotty = import 'github.com/metio/kurly/workloads/jotty/server.libsonnet';
//   kurly.list(jotty())
//
// Serves the web app and API on :3000 — compose an exposure onto it.
//
// TWO VOLUMES, because it writes in two places and they hold different things:
// /app/data is the notes, checklists, users, sessions and encryption keys, and
// /app/config is what an administrator customises from the settings page (themes,
// emojis, custom CSS). The image ships defaults for the second, which the mount
// hides — jotty falls back to an empty configuration for each, so a fresh volume
// is a jotty with no customisation rather than a broken one.
//
// Single writer: files on ReadWriteOnce volumes, so one replica, recreated (never
// rolled) — two pods writing the same Markdown tree is not something anything here
// reconciles afterwards.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='jotty',
  image=defaultImage,
  storageSize='5Gi',
  configSize='1Gi',
  storageClass=null,
  // The public URL, when jotty sits behind a proxy that terminates TLS — it
  // builds absolute links from it. Absent by default: a wrong one is worse than
  // none, and relative links work until it is exposed.
  appUrl=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = if appUrl == null then {} else { APP_URL: appUrl, HTTPS: if std.startsWith(appUrl, 'https://') then 'true' else 'false' };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.env(baseEnv + env)
  // The entrypoint only reaches for su-exec when it starts as root; running as
  // 1000:1000 — the account the image builds and chowns its own tree to — it
  // execs the server directly and needs no privilege to drop.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/app/data', storageSize, storageClass=storageClass)
  + kurly.store('/app/config', configSize, storageClass=storageClass)
  // Next.js writes its incremental render cache inside its own tree, and the
  // standalone server keeps temporary uploads in /tmp.
  + kurly.scratch('/app/.next/cache')
  + kurly.scratch('/tmp')
  + kurly.readinessProbe({ httpGet: { path: '/api/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/health', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
