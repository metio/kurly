// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// answer — an Apache Answer server (a self-hosted Q&A platform for building a
// community knowledge base, à la Stack Overflow). A plain composable kurly.http
// workload on the official image: with the SQLite backend its data and uploads live
// on a PersistentVolume, so it needs no external database. Import it and render with
// kurly.list:
//
//   local answer = import 'github.com/metio/kurly/workloads/answer/server.libsonnet';
//   kurly.list(answer())
//
// Serves the web app and API on :80 — compose an exposure onto it.
//
// Single writer: the SQLite database and uploads live on a ReadWriteOnce volume, so
// one replica, recreated (never rolled) to keep two pods off the files. Configure an
// external PostgreSQL/MySQL through the installer to scale past that.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='answer',
  image='docker.io/apache/answer:v2.0.1',
  storageSize='5Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + (if env == {} then {} else kurly.env(env))
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
