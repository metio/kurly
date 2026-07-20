// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// onlyoffice — an ONLYOFFICE Document Server (a self-hosted online office suite for
// collaborative editing of documents, spreadsheets and presentations; the editor Nextcloud,
// Seafile and others embed). A plain composable kurly.http workload on the official image; its
// data lives on a PersistentVolume. Import it, point it at its secret, and render with
// kurly.list:
//
//   local onlyoffice = import 'github.com/metio/kurly/workloads/onlyoffice/server.libsonnet';
//   kurly.list(onlyoffice())
//
// Serves the document server on :80 — compose an exposure onto it; the app that embeds it (e.g.
// Nextcloud) points its ONLYOFFICE connector at this URL.
//
// SECRET: the JWT the connector signs its requests with comes from JWT_SECRET. kurly authors no
// Secret; provide one holding it, via envFrom. The image bundles its own PostgreSQL and
// RabbitMQ, so it runs as root; point it at external ones for a larger deployment.
//
// Single writer: the data lives on a ReadWriteOnce volume, so one replica, recreated.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='onlyoffice',
  image='docker.io/onlyoffice/documentserver:8.2.1',
  storageSize='10Gi',
  storageClass=null,
  secretName='onlyoffice-secrets',
  env={},
  resources={ requests: { cpu: '250m', memory: '1Gi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.envFromSecret(secretName)
  + kurly.env({ JWT_ENABLED: 'true' } + env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/var/www/onlyoffice/Data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/healthcheck', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
