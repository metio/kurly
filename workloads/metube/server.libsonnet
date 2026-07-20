// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// metube — a MeTube server (a web UI for yt-dlp: paste a video or playlist URL and it
// downloads it to a directory, with format and quality options). A plain composable
// kurly.http workload on the official image; downloaded files live on a PersistentVolume.
// Import it and render with kurly.list:
//
//   local metube = import 'github.com/metio/kurly/workloads/metube/server.libsonnet';
//   kurly.list(metube())
//
// Serves the web app on :8081 — compose an exposure onto it.
//
// Single writer: downloads live on a ReadWriteOnce volume, so one replica, recreated.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='metube',
  image='ghcr.io/alexta69/metube:2026.07.18',
  storageSize='50Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8081)
  + kurly.servicePort(8081)
  + kurly.env({ DOWNLOAD_DIR: '/downloads', STATE_DIR: '/downloads/.metube' } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/downloads', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
