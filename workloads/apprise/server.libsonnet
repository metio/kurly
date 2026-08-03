// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// apprise — an Apprise API server (a self-hosted push-notification relay that fans one request out
// to 100+ services: email, Slack, Telegram, ntfy, webhooks, …). A plain composable kurly.http
// workload on the official image; persistent, named notification configurations live on a
// PersistentVolume under /config. Import it and render with kurly.list:
//
//   local apprise = import 'github.com/metio/kurly/workloads/apprise/server.libsonnet';
//   kurly.list(apprise())
//
// Serves the API on :8000 — compose an exposure onto it. It can also run purely stateless
// (stateless POST with inline URLs); drop the store if you never persist named configs.
//
// Single writer: the config store is a ReadWriteOnce volume, so one replica, recreated (never
// rolled) to keep two pods off the same config directory.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');
function(
  name='apprise',
  image=defaultImage,
  storageSize='1Gi',
  storageClass=null,
  // Cap gunicorn at two workers — the default scales with CPU count and each
  // worker's memory adds up fast on a many-core node.
  env={ APPRISE_STATEFUL_MODE: 'simple', APPRISE_WORKER_COUNT: '2' },
  // nginx + gunicorn workers + supervisord together exceed 256Mi and OOMKill.
  resources={ requests: { cpu: '50m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8000)
  + kurly.servicePort(8000)
  + kurly.env(env)
  // The image declares root, but it runs as an ordinary uid: its files are
  // world-readable and everything it writes is under a volume fsGroup owns.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // Everything is dropped and these are granted back by name — the
  // smallest set this image was observed to boot with.
  + kurly.addCapabilities(['CHOWN', 'SETGID', 'SETUID'])
  + kurly.writableRootFilesystem()
  + kurly.store('/config', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/status', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/status', port: 'http' } })
  // supervisord brings up gunicorn + nginx; a startup probe holds liveness until
  // the HTTP port is actually serving.
  + kurly.startupProbe({ httpGet: { path: '/status', port: 'http' }, failureThreshold: 30, periodSeconds: 5 })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
