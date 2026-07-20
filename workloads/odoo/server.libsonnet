// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// odoo — an Odoo server (a self-hosted, all-in-one business/ERP suite: CRM, sales, inventory,
// accounting, website and more, as installable apps). A plain composable kurly.http workload
// on the official image, backed by an external PostgreSQL, with its filestore on a
// PersistentVolume. Import it, point it at a database, and render with kurly.list:
//
//   local odoo = import 'github.com/metio/kurly/workloads/odoo/server.libsonnet';
//   kurly.list(odoo())
//
// Serves the web app on :8069 — compose an exposure onto it.
//
// DATABASE & SECRETS: Odoo reads its PostgreSQL connection from HOST, USER and PASSWORD (or a
// mounted odoo.conf). kurly authors no Secret; provide one holding them, via envFrom. Pairs
// with a cnpg-cluster named odoo-db.
//
// Single writer: the filestore lives on a ReadWriteOnce volume, so one replica, recreated
// (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='odoo',
  image='docker.io/odoo:18.0',
  storageSize='20Gi',
  storageClass=null,
  secretName='odoo-secrets',
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8069)
  + kurly.servicePort(8069)
  + kurly.envFromSecret(secretName)
  + kurly.env(env)
  + kurly.runAs(101, gid=101, fsGroup=101)
  + kurly.writableRootFilesystem()
  + kurly.store('/var/lib/odoo', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
