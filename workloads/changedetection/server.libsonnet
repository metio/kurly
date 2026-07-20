// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// changedetection — a changedetection.io server (self-hosted "website change detection":
// watch pages and get notified when they change, with optional visual-diff and price
// tracking). A plain composable kurly.http workload on the official image; its datastore
// (SQLite plus page snapshots) lives on a PersistentVolume, so it needs no external
// database. Import it, adapt with the parameters below, and render with kurly.list:
//
//   local changedetection = import 'github.com/metio/kurly/workloads/changedetection/server.libsonnet';
//   kurly.list(changedetection(baseUrl='https://watch.example.com'))
//
// Serves the web app on :5000 — compose an exposure onto it.
//
// JAVASCRIPT PAGES: fetching pages that need a browser requires a companion Playwright
// or Sockpuppetbrowser/Chrome service; point PLAYWRIGHT_DRIVER_URL at it (via env). The
// plain HTTP fetcher works without it.
//
// Single writer: the datastore lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='changedetection',
  image='ghcr.io/dgtlmoon/changedetection.io:0.55.8',
  storageSize='5Gi',
  storageClass=null,
  // The public URL (changedetection builds notification links from it).
  baseUrl=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = if baseUrl == null then {} else { BASE_URL: baseUrl };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(5000)
  + kurly.servicePort(5000)
  + kurly.env({ DATASTORE_PATH: '/datastore' } + baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/datastore', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
