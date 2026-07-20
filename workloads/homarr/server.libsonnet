// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// homarr — a Homarr server (a sleek, self-hosted dashboard for your homelab: pin your
// services, search across them, and watch their status in one place). A plain
// composable kurly.http workload on the official image; its SQLite database and config
// live on a PersistentVolume, so it needs no external database. Import it, adapt with
// the parameters below, and render with kurly.list:
//
//   local homarr = import 'github.com/metio/kurly/workloads/homarr/server.libsonnet';
//   kurly.list(homarr())
//
// Serves the dashboard on :7575 — compose an exposure onto it.
//
// SECRET: Homarr encrypts stored integration credentials with SECRET_ENCRYPTION_KEY (a
// 64-character hex string). kurly authors no Secret; provide one holding it, pulled in
// via envFrom.
//
// Single writer: the SQLite database lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='homarr',
  image='ghcr.io/homarr-labs/homarr:v1.71.0',
  storageSize='1Gi',
  storageClass=null,
  // The Secret holding SECRET_ENCRYPTION_KEY (kurly mints none), via envFrom.
  secretName='homarr-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(7575)
  + kurly.servicePort(7575)
  + kurly.envFromSecret(secretName)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/appdata', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
