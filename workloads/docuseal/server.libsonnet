// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// docuseal — a DocuSeal server (a self-hosted document-signing platform: build fillable
// PDF forms and collect legally-binding e-signatures, an open alternative to DocuSign).
// A plain composable kurly.http workload on the official image; with the default SQLite
// backend its database and uploaded documents live on a PersistentVolume. Import it,
// adapt with the parameters below, and render with kurly.list:
//
//   local docuseal = import 'github.com/metio/kurly/workloads/docuseal/server.libsonnet';
//   kurly.list(docuseal())
//
// Serves the web app and API on :3000 — compose an exposure onto it.
//
// DATABASE: point DocuSeal at an external PostgreSQL through DATABASE_URL (from a Secret
// via kurly.envFromSecret) to scale past the single SQLite writer.
//
// Single writer: the SQLite database and documents live on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='docuseal',
  image='docker.io/docuseal/docuseal:3.1.5',
  storageSize='10Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
