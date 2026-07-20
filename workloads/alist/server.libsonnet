// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// alist — an AList server (a self-hosted file list / WebDAV program fronting many storage backends
// — local disk, S3, WebDAV, cloud drives — behind one web UI). A plain composable kurly.http
// workload on the official image; its SQLite database and configuration live on a PersistentVolume
// under /opt/alist/data. Import it and render with kurly.list:
//
//   local alist = import 'github.com/metio/kurly/workloads/alist/server.libsonnet';
//   kurly.list(alist())
//
// Serves the web UI and WebDAV on :5244 — compose an exposure onto it. On first start it logs a
// randomly generated admin password; read it from the pod logs (or set one via the CLI).
//
// Single writer: the SQLite database lives on a ReadWriteOnce volume, so one replica, recreated
// (never rolled) to keep two pods off the same database.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='alist',
  image='ghcr.io/alistgo/alist:latest@sha256:ee46012c344c0f40387b1c1aeddee4c114887764d3aebdd1d7bba83920423c5e',
  storageSize='5Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(5244)
  + kurly.servicePort(5244)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/opt/alist/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/ping', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/ping', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
