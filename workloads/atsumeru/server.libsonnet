// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// atsumeru — an Atsumeru server (a media server for manga, comics and light
// novels). A plain composable kurly.http workload on the official image: it keeps
// its database, configuration, cover cache and logs on a PersistentVolume and
// reads its library from the same volume, so it needs no external database.
// Import it and render with kurly.list:
//
//   local atsumeru = import 'github.com/metio/kurly/workloads/atsumeru/server.libsonnet';
//   kurly.list(atsumeru())
//
// Serves the web UI and the REST API on :31337 — compose an exposure onto it. Put
// your manga and comic archives under /library on the volume.
//
// The admin password is PRINTED TO THE LOG on the first start and stored nowhere
// else, so read the pod's log after the first rollout.
//
// The JVM writes temp files to the root filesystem, so this relaxes the
// read-only-rootfs default while keeping non-root, dropped capabilities, and no
// privilege escalation.
//
// Probes are connection probes: the server answers /api/server/ping with a 4xx
// while it is up and unauthenticated (its own healthcheck greps for exactly that),
// which an httpGet probe reads as a failure and would restart the pod forever.
//
// Single writer: the database lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='atsumeru',
  image=defaultImage,
  storageSize='50Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '1536Mi' } },
  labels={},
  annotations={},
)
  // Atsumeru keeps its configuration, database, cover cache and logs in separate
  // directories beside the jar, and reads the library from /library; surface all
  // of them as subpaths of the same volume as the configuration.
  local extraDirs = {
    deployment+: { spec+: { template+: { spec+: {
      containers: [
        container { volumeMounts+: [
          { name: 'store', mountPath: '/app/database', subPath: 'database' },
          { name: 'store', mountPath: '/app/cache', subPath: 'cache' },
          { name: 'store', mountPath: '/app/logs', subPath: 'logs' },
          { name: 'store', mountPath: '/library', subPath: 'library' },
        ] }
        for container in super.containers
      ],
    } } } },
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(31337)
  + kurly.servicePort(31337)
  + (if env == {} then {} else kurly.env(env))
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/app/config', storageSize, storageClass=storageClass)
  // A JVM starting on a fresh database indexes nothing yet but still takes a
  // while to listen, and nothing answers until it does.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 30 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + extraDirs
