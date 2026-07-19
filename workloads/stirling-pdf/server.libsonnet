// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// stirling-pdf — a Stirling-PDF server (a locally-hosted web toolkit for splitting,
// merging, converting, and editing PDFs). A plain composable kurly.http workload on
// the official image: it processes files in memory and keeps its configuration and
// custom files on a PersistentVolume, so it needs no external database. Import it
// and render with kurly.list:
//
//   local stirling = import 'github.com/metio/kurly/workloads/stirling-pdf/server.libsonnet';
//   kurly.list(stirling())
//
// Serves the web UI and API on :8080 — compose an exposure onto it.
//
// The image runs LibreOffice and other tools and writes across the root filesystem,
// so this relaxes the read-only-rootfs default while keeping non-root, dropped
// capabilities, and no privilege escalation.
//
// Single writer: the configuration and custom files live on a ReadWriteOnce volume,
// so one replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='stirling-pdf',
  image='docker.io/stirlingtools/stirling-pdf:2.14.2',
  storageSize='1Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + (if env == {} then {} else kurly.env(env))
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/configs', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/api/v1/info/status', port: 'http' }, initialDelaySeconds: 20, periodSeconds: 15, failureThreshold: 12 })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' }, initialDelaySeconds: 30 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
