// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// lychee — a Lychee server (a self-hosted photo-management and gallery system). A
// plain composable kurly.http workload on the official image: with the SQLite backend
// its config, database, and photos live on a PersistentVolume, so it needs no external
// database. Import it and render with kurly.list:
//
//   local lychee = import 'github.com/metio/kurly/workloads/lychee/server.libsonnet';
//   kurly.list(lychee(appUrl='https://photos.example.com'))
//
// Serves the gallery and API on :80 — compose an exposure onto it.
//
// The nginx + PHP-FPM image starts as root and binds :80, so this relaxes kurly's
// non-root and read-only-rootfs defaults while keeping dropped capabilities and no
// privilege escalation.
//
// Single writer: config, database, and photos live on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the files. Point DB_CONNECTION
// at external MySQL/PostgreSQL to scale past the single SQLite writer.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='lychee',
  image='docker.io/lycheeorg/lychee:v7.7.1',
  storageSize='20Gi',
  storageClass=null,
  // The public URL Lychee builds links against (required).
  appUrl=null,
  // The Secret holding APP_KEY (kurly mints none), via envFrom.
  secretName='lychee-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    DB_CONNECTION: 'sqlite',
  } + (if appUrl == null then {} else { APP_URL: appUrl });

  // Lychee keeps its config, database, and photos in separate trees; surface config
  // and sym as subpaths of the same volume as uploads.
  local extraDirs = {
    deployment+: { spec+: { template+: { spec+: {
      containers: [
        container { volumeMounts+: [
          { name: 'store', mountPath: '/conf', subPath: 'conf' },
          { name: 'store', mountPath: '/sym', subPath: 'sym' },
        ] }
        for container in super.containers
      ],
    } } } },
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/uploads', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + extraDirs
