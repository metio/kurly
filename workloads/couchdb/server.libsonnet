// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// couchdb — an Apache CouchDB server (a self-hosted, document-oriented NoSQL database that
// speaks HTTP/JSON and syncs seamlessly with offline-first apps via its replication
// protocol). A plain composable kurly.http workload on the official image; its data lives on
// a PersistentVolume. Import it, point it at its admin secret, and render with kurly.list:
//
//   local couchdb = import 'github.com/metio/kurly/workloads/couchdb/server.libsonnet';
//   kurly.list(couchdb())
//
// Serves the HTTP API and Fauxton UI on :5984 — often reached in-cluster (http://couchdb:5984).
//
// SECRET: CouchDB reads its admin credentials from COUCHDB_USER and COUCHDB_PASSWORD. kurly
// authors no Secret; provide one holding them, pulled in via envFrom.
//
// Single writer: the data lives on a ReadWriteOnce volume, so one replica, recreated (never
// rolled) to keep two pods off the storage.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='couchdb',
  image='docker.io/library/couchdb:3.4.2',
  storageSize='10Gi',
  storageClass=null,
  secretName='couchdb-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(5984)
  + kurly.servicePort(5984)
  + kurly.envFromSecret(secretName)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/opt/couchdb/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/_up', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/_up', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
