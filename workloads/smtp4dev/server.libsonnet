// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// smtp4dev — an smtp4dev server (a self-hosted fake SMTP server for development: it receives the
// mail your apps send and shows it in a web UI, without delivering anything onward). A plain
// composable kurly.http workload on the official image, listening on TWO ports — the web UI and the
// SMTP sink — so it uses kurly.extraPort for the second. Its message database lives on a
// PersistentVolume under /smtp4dev. Import it and render with kurly.list:
//
//   local smtp4dev = import 'github.com/metio/kurly/workloads/smtp4dev/server.libsonnet';
//   kurly.list(smtp4dev())
//
// Serves the web UI on :80 and accepts SMTP on :25 — point your apps' SMTP client at the Service on
// port 25, and compose an exposure onto the web port.
//
// Single writer: the message database is a ReadWriteOnce volume, so one replica, recreated (never
// rolled) to keep two pods off the same database.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='smtp4dev',
  image='docker.io/rnwood/smtp4dev:latest@sha256:25c434c1900a9c5b61e17ead0a774d9e81b80554d05cf64719d69e5ea8c66537',
  storageSize='2Gi',
  storageClass=null,
  env={ ServerOptions__Database: '/smtp4dev/database.db' },
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.extraPort('smtp', 25)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/smtp4dev', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
