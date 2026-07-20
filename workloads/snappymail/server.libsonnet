// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// snappymail — a SnappyMail server (a fast, modern, self-hosted webmail client that connects to
// your existing IMAP/SMTP mail servers). A plain composable kurly.http workload on the official
// image; its configuration and per-account data live on a PersistentVolume. Import it and render
// with kurly.list:
//
//   local snappymail = import 'github.com/metio/kurly/workloads/snappymail/server.libsonnet';
//   kurly.list(snappymail())
//
// Serves the web app on :8888 — compose an exposure onto it. Configure your IMAP/SMTP servers in
// the admin panel; SnappyMail is a client and does not run a mail server itself.
//
// The image publishes only a rolling tag, so it is pinned by digest here; Renovate resolves and
// updates the digest. The bundled server runs as root.
//
// Single writer: the data lives on a ReadWriteOnce volume, so one replica, recreated.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='snappymail',
  image='ghcr.io/the-djmaze/snappymail:latest@sha256:5e3d990438809a8a49f8ac5758db03e858e6e9fc0e369e1f9e474f7664079905',
  storageSize='2Gi',
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
  + kurly.port(8888)
  + kurly.servicePort(8888)
  + kurly.env(env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/var/lib/snappymail', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
