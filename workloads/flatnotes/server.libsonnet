// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// flatnotes — a flatnotes server (a self-hosted, database-less note-taking app that
// stores everything as flat markdown files). A plain composable kurly.http
// workload: your notes live on a PersistentVolume, so it needs no external database.
// Import it and render with kurly.list:
//
//   local flatnotes = import 'github.com/metio/kurly/workloads/flatnotes/server.libsonnet';
//   kurly.list(flatnotes())
//
// Serves the web app and API on :8080 — compose an exposure onto it.
//
// AUTH: flatnotes reads FLATNOTES_AUTH_TYPE and its credentials/secret key from the
// environment. kurly authors no Secret; provide one holding FLATNOTES_USERNAME,
// FLATNOTES_PASSWORD, and FLATNOTES_SECRET_KEY, pulled in via envFrom.
//
// Single writer: the markdown files live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='flatnotes',
  image='docker.io/dullage/flatnotes:v5.5.4',
  storageSize='1Gi',
  storageClass=null,
  // The Secret holding FLATNOTES_USERNAME, FLATNOTES_PASSWORD, and
  // FLATNOTES_SECRET_KEY (kurly mints none), via envFrom.
  secretName='flatnotes-secrets',
  env={},
  resources={ requests: { cpu: '25m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.envFromSecret(secretName)
  + kurly.env({ FLATNOTES_PATH: '/data', PUID: '1000', PGID: '1000' } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '32Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
