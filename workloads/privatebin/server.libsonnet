// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// privatebin — a PrivateBin server (a minimalist, open-source, zero-knowledge pastebin:
// the server stores only encrypted blobs — pastes are encrypted and decrypted in the
// browser). A plain composable kurly.http workload on the official nginx+php-fpm image;
// with the default filesystem backend its encrypted pastes live on a PersistentVolume.
// Import it and render with kurly.list:
//
//   local privatebin = import 'github.com/metio/kurly/workloads/privatebin/server.libsonnet';
//   kurly.list(privatebin())
//
// Serves the web app on :8080 — compose an exposure onto it.
//
// Single writer: the paste store lives on a ReadWriteOnce volume, so one replica,
// recreated. Point PrivateBin at an external database (its conf.php) to scale out.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='privatebin',
  image='docker.io/privatebin/nginx-fpm-alpine:2.0.5',
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
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env(env)
  // The bundled nginx and php-fpm masters run as root then serve as an unprivileged user;
  // the root filesystem stays writable for their runtime state.
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/srv/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
