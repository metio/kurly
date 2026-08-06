// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// gerbera — a Gerbera server (a DLNA media server streaming a personal
// library to televisions, players and phones on the same network). A plain
// composable kurly.http workload on the official image: it keeps its config.xml
// and SQLite database on a PersistentVolume and reads the library from it, so it
// needs no external database. Import it and render with kurly.list:
//
//   local gerbera = import 'github.com/metio/kurly/workloads/gerbera/server.libsonnet';
//   kurly.list(gerbera())
//
// Serves the web UI and the DLNA HTTP endpoints on :49494 — compose an exposure
// onto it. Put your media under /content on the volume; the generated config
// autoscans it with inotify.
//
// DLNA discovery is SSDP multicast on 1900/udp, which does not cross a pod
// network: players on the LAN will not find this by themselves. Point them at the
// exposed address, or run it on the host network, which is a decision for the
// consumer and not something a workload should assume.
//
// Single writer: config and database live on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='gerbera',
  image=defaultImage,
  storageSize='50Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  // Gerbera reads the library from /content (the image symlinks /mnt/content at
  // it, which is what the generated autoscan entry names); keep it a subpath of
  // the same volume as the config.
  local library = {
    deployment+: { spec+: { template+: { spec+: {
      containers: [
        container { volumeMounts+: [{ name: 'store', mountPath: '/content', subPath: 'content' }] }
        for container in super.containers
      ],
    } } } },
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(49494)
  + kurly.servicePort(49494)
  + (if env == {} then {} else kurly.env(env))
  // The entrypoint generates the config, chowns the volume and drops to the
  // image's own account with su-exec, so the container starts as root and the
  // server itself does not run as one.
  + kurly.rootUser()
  + kurly.addCapabilities(['CHOWN', 'FOWNER', 'SETGID', 'SETUID'])
  + kurly.store('/var/run/gerbera', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp')
  // A Service named after the workload injects GERBERA_PORT as a tcp:// URL, and
  // Gerbera reads GERBERA_* as configuration.
  + kurly.disableServiceLinks()
  // The first start writes a config.xml and builds the database before anything
  // binds; gate liveness until it does.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 5, failureThreshold: 60 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + library
