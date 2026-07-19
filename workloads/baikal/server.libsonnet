// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// baikal — a Baïkal server (a lightweight CalDAV + CardDAV server built on
// sabre/dav). A plain composable kurly.http workload on the maintained ckulka
// image: it keeps its configuration and its SQLite database on a PersistentVolume,
// so it needs no external database by default. Import it and render with
// kurly.list:
//
//   local baikal = import 'github.com/metio/kurly/workloads/baikal/server.libsonnet';
//   kurly.list(baikal())
//
// Serves the admin UI and CalDAV/CardDAV on :80 — compose an exposure onto it.
// Point it at an external MySQL/PostgreSQL through the setup wizard to scale past
// the single SQLite writer.
//
// The nginx + PHP-FPM image starts as root and binds :80, so this relaxes kurly's
// non-root and read-only-rootfs defaults while keeping dropped capabilities and no
// privilege escalation.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='baikal',
  image='docker.io/ckulka/baikal:0.10.1-nginx',
  storageSize='2Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  // Baïkal persists both its database (/Specific) and its generated configuration
  // (/config). Surface the config directory as a subpath of the same volume so
  // both survive a restart.
  local configMount = {
    deployment+: { spec+: { template+: { spec+: {
      containers: [
        container { volumeMounts+: [{ name: 'store', mountPath: '/var/www/baikal/config', subPath: 'config' }] }
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
  + (if env == {} then {} else kurly.env(env))
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/var/www/baikal/Specific', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + configMount
