// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// minio — a MinIO server (a high-performance, self-hosted, S3-compatible object storage
// server). A plain composable kurly.http workload on the official image; its objects live on
// a PersistentVolume. Import it, point it at its credentials, and render with kurly.list:
//
//   local minio = import 'github.com/metio/kurly/workloads/minio/server.libsonnet';
//   kurly.list(minio())
//
// Serves the S3 API on :9000 — usually reached in-cluster (http://minio:9000). The web console
// runs on :9001, published on the Service beside the S3 port (the 'console' port).
//
// SECRET: MinIO reads MINIO_ROOT_USER and MINIO_ROOT_PASSWORD from the environment. kurly
// authors no Secret; provide one holding them, via envFrom.
//
// Single writer: the objects live on a ReadWriteOnce volume, so one replica, recreated. This
// is a single-node MinIO; a real object store runs distributed MinIO across nodes/disks.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='minio',
  image='docker.io/minio/minio:RELEASE.2024-11-07T00-52-20Z',
  storageSize='50Gi',
  storageClass=null,
  secretName='minio-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(9000)
  + kurly.servicePort(9000)
  + kurly.extraPort('console', 9001)
  + kurly.args(['server', '/data', '--console-address', ':9001'])
  + kurly.envFromSecret(secretName)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/minio/health/ready', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/minio/health/live', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
