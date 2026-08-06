// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// polaris — a Polaris server (a music streaming server for your own collection,
// with a web client and a documented HTTP API). A plain composable kurly.http
// workload: it keeps its database, its cache and the music library on one
// PersistentVolume, so it needs no external database. Import it and render with
// kurly.list:
//
//   local polaris = import 'github.com/metio/kurly/workloads/polaris/server.libsonnet';
//   kurly.list(polaris())
//
// Serves the web client and the API on :5050 — compose an exposure onto it. Put
// your music under /music on the volume; Polaris indexes the directories you add
// in its settings.
//
// SERVICE LINKS: the image's run-polaris wrapper reads POLARIS_PORT as the port to
// listen on, and a Service named after this workload makes Kubernetes inject
// POLARIS_PORT as a tcp:// URL. The wrapper is bypassed here and service links are
// disabled, so neither half of that can bite.
//
// Single writer: the database lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='polaris',
  image=defaultImage,
  storageSize='50Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  // The cache (thumbnails, audio peaks) and the music library share the store with
  // the database, each under its own subPath: rebuilding thumbnails costs a full
  // rescan, so the cache is worth keeping across restarts.
  local volumes = {
    deployment+: { spec+: { template+: { spec+: {
      containers: [
        container {
          volumeMounts+: [
            { name: 'store', mountPath: '/var/cache/polaris', subPath: 'cache' },
            { name: 'store', mountPath: '/music', subPath: 'music' },
          ],
        }
        for container in super.containers
      ],
    } } } },
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(5050)
  + kurly.servicePort(5050)
  + kurly.disableServiceLinks()
  // The image's run-polaris wrapper builds its arguments from POLARIS_* variables
  // and passes the data directory as `-d`, which this version of polaris no longer
  // accepts — and its defaults are derived from HOME, which the image does not set.
  // Calling the binary directly states every path instead.
  + kurly.command(['polaris'])
  + kurly.args([
    '--foreground',
    '-p',
    '5050',
    '--data',
    '/var/lib/polaris',
    '--cache',
    '/var/cache/polaris',
    '--config',
    '/var/lib/polaris/polaris.toml',
  ])
  + kurly.env(env)
  // The image's own polaris user, uid/gid 100; fsGroup hands it the volume.
  + kurly.runAs(100, gid=100, fsGroup=100)
  + kurly.store('/var/lib/polaris', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ httpGet: { path: '/api/version', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + volumes
