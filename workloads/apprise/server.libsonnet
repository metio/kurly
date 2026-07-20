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
function(
  name='apprise',
  image='docker.io/caronc/apprise:latest@sha256:91321755496e8472bdb674e4b14eb64d1f3b15510ef94971309c9f76ef3171e7',
  storageSize='1Gi',
  storageClass=null,
  env={ APPRISE_STATEFUL_MODE: 'simple' },
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
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
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/config', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/status', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/status', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
