// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// homer — a Homer server (a simple, static dashboard for your self-hosted
// services). A plain composable kurly.http workload on the official image: its
// configuration and custom assets live on a PersistentVolume, so it needs no
// external database. Import it and render with kurly.list:
//
//   local homer = import 'github.com/metio/kurly/workloads/homer/server.libsonnet';
//   kurly.list(homer())
//
// Serves the dashboard on :8080 — compose an exposure onto it. Edit
// /www/assets/config.yml on the volume to configure it (the image seeds defaults on
// first start via INIT_ASSETS).
//
// Single writer: the assets live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='homer',
  image='docker.io/b4bz/homer:v26.4.2',
  storageSize='1Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '25m', memory: '32Mi' }, limits: { memory: '64Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env({ INIT_ASSETS: '1' } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/www/assets', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
