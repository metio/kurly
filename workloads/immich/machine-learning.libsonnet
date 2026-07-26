// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// immich machine-learning — the inference service Immich's server calls for
// smart search, face recognition, and object tagging. It downloads models on
// demand into a cache on a PersistentVolume mounted at /cache, so the models
// survive a restart rather than re-downloading. The server reaches it through
// its Service at http://<name>:3003 (the IMMICH_MACHINE_LEARNING_URL the server
// stage defaults to). Compose it beside the server stage:
//
//   local ml = import 'github.com/metio/kurly/workloads/immich/machine-learning.libsonnet';
//   kurly.list(ml())
//
// The model cache is a ReadWriteOnce volume, so one replica, recreated.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './machine-learning.image', '\n');

function(
  name='immich-machine-learning',
  image=defaultImage,
  storageSize='10Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '4Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3003)
  + kurly.servicePort(3003)
  // Runs as root in the official image and writes its model cache under /cache;
  // pin a non-root uid that owns the volume and keep the root filesystem
  // writable for the model downloads and the ML runtime's scratch files.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/cache', storageSize, storageClass=storageClass)
  + kurly.env({ MACHINE_LEARNING_CACHE_FOLDER: '/cache' } + env)
  + kurly.readinessProbe({ httpGet: { path: '/ping', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/ping', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
