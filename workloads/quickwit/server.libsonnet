// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// quickwit — a search engine for logs, traces and other append-only data, built
// to index straight onto object storage. A plain composable kurly.http workload
// running every Quickwit service in one process. Import it and render with
// kurly.list:
//
//   local quickwit = import 'github.com/metio/kurly/workloads/quickwit/server.libsonnet';
//   kurly.list(quickwit())
//
// Serves the REST API, the UI and the Elasticsearch-compatible API on :7280 —
// compose an exposure onto it.
//
// WHERE THE INDEX LIVES. By default the whole index is on the PersistentVolume,
// which is the arrangement that works with no other infrastructure and does not
// grow past one node. `defaultIndexRootUri` pointed at an S3 bucket
// (`s3://bucket/indexes`) is what Quickwit is actually built for: the split files
// go to object storage and the volume keeps only the metastore and local caches.
// The credentials for that bucket come from `secretName` (AWS_ACCESS_KEY_ID,
// AWS_SECRET_ACCESS_KEY) — kurly authors no Secret.
//
// Single writer: the file-backed metastore is one directory on a ReadWriteOnce
// volume, so one replica, recreated (never rolled). A cluster wants a PostgreSQL
// metastore and separately scaled indexer and searcher roles, which is a
// different arrangement than this one stage.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='quickwit',
  image=defaultImage,
  storageSize='20Gi',
  storageClass=null,
  // Where index splits are written; an s3:// URI moves them off the volume.
  defaultIndexRootUri=null,
  // A Secret carrying the object-storage credentials, read through envFrom.
  secretName=null,
  env={},
  resources={ requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '4Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(7280)
  + kurly.servicePort(7280)
  // The gossip and gRPC ports every Quickwit node expects to find its peers on;
  // published so a second deployment could be pointed at this one.
  + kurly.extraPort('gossip', 7280, protocol='UDP')
  + kurly.extraPort('grpc', 7281)
  + kurly.args(['run'])
  + kurly.env(
    {
      QW_DATA_DIR: '/quickwit/qwdata',
      QW_LISTEN_ADDRESS: '0.0.0.0',
    }
    + (if defaultIndexRootUri != null then { QW_DEFAULT_INDEX_ROOT_URI: defaultIndexRootUri } else {})
    + env
  )
  // The image runs as root by default; nothing in it is owned by a runtime user,
  // so an unprivileged uid with fsGroup over the data directory serves.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/quickwit/qwdata', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '1Gi')
  + (if secretName != null then kurly.envFromSecret(secretName) else {})
  + kurly.readinessProbe({ httpGet: { path: '/health/readyz', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/health/livez', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
