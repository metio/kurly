// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// commafeed — a CommaFeed server (a self-hosted Google Reader-style RSS/Atom feed
// reader). A plain composable kurly.http workload on the official image: the H2
// variant keeps its feeds and articles in an embedded database on a PersistentVolume,
// so it needs no external database. Import it and render with kurly.list:
//
//   local commafeed = import 'github.com/metio/kurly/workloads/commafeed/server.libsonnet';
//   kurly.list(commafeed())
//
// Serves the web app and API on :8082 — compose an exposure onto it.
//
// Single writer: the embedded H2 database lives on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the file. Use the PostgreSQL
// image variant (athou/commafeed:<version>-postgresql) and point CF_APP_DATABASE at a
// cnpg-cluster to scale past that.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='commafeed',
  image='docker.io/athou/commafeed:7.2.0-h2',
  storageSize='2Gi',
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
  + kurly.port(8082)
  + kurly.servicePort(8082)
  + kurly.env({ CF_APP_DATABASE_H2_FILE: '/commafeed/data/db/commafeed', QUARKUS_HTTP_PORT: '8082' } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/commafeed/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
