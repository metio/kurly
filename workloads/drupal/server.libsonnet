// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// drupal — a A Drupal server (a powerful, self-hosted open-source CMS and content framework (backed by MySQL/PostgreSQL)). A plain composable kurly.http workload on the official image,
// backed by an external database, with its data on a PersistentVolume (the image populates it
// on first run). Import it, point it at a database, and render with kurly.list:
//
//   local drupal = import 'github.com/metio/kurly/workloads/drupal/server.libsonnet';
//   kurly.list(drupal())
//
// Serves the web app on :80 — compose an exposure onto it.
//
// DATABASE & SECRETS: it reads its database connection from the environment. kurly authors no
// Secret; provide one holding the DB credentials, via envFrom.
//
// Single writer: the data lives on a ReadWriteOnce volume, so one replica, recreated. The
// Apache master runs as root then serves as www-data.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='drupal',
  image='docker.io/library/drupal:11.0',
  storageSize='10Gi',
  storageClass=null,
  secretName='drupal-secrets',
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
  + kurly.envFromSecret(secretName)
  + kurly.env({} + env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/var/www/html/sites', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
