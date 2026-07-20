// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mailpit — a Mailpit server (a self-hosted email- and SMTP-testing tool: it catches every message
// your apps send and shows them in a web UI, with a real SMTP sink and an API). A plain composable
// kurly.http workload on the official image, listening on TWO ports — the web UI/API and the SMTP
// sink — so it uses kurly.extraPort for the second. Its message store (SQLite) lives on a
// PersistentVolume under /data. Import it and render with kurly.list:
//
//   local mailpit = import 'github.com/metio/kurly/workloads/mailpit/server.libsonnet';
//   kurly.list(mailpit())
//
// Serves the web UI and API on :8025 and accepts SMTP on :1025 — point your apps' SMTP client at
// the Service on port 1025, and compose an exposure onto the web port.
//
// Single writer: the message store is a ReadWriteOnce volume, so one replica, recreated (never
// rolled) to keep two pods off the same database.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='mailpit',
  image='docker.io/axllent/mailpit:latest@sha256:b868afa176bfd6cce2323ea316cd99ccad77915e51e595748f6d786700ecf109',
  storageSize='2Gi',
  storageClass=null,
  env={ MP_DATABASE: '/data/mailpit.db' },
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8025)
  + kurly.servicePort(8025)
  + kurly.extraPort('smtp', 1025)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/readyz', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/livez', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
