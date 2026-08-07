// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// crafty-controller — a Crafty Controller server (a web control panel that
// installs, starts, stops and backs up Minecraft servers, and runs them as child
// processes of itself). A composable kurly.http workload with the panel's own
// state, the game servers it manages, and their backups each on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local crafty = import 'github.com/metio/kurly/workloads/crafty-controller/server.libsonnet';
//   kurly.list(crafty())
//
// SERVES HTTPS ON :8443, WITH A SELF-SIGNED CERTIFICATE IT MINTS ITSELF — there
// is no plaintext listener at all, so an exposure composed onto it must talk TLS
// to the backend (the Ingress annotation or the HTTPRoute BackendTLSPolicy your
// controller uses). Probes are by CONNECTION for the same reason.
//
// THE GAME SERVERS RUN INSIDE THIS POD. Crafty launches each Minecraft server as
// its own JVM under the panel process, so the pod's memory and CPU limits are the
// budget for every server it hosts, not just for the panel — the defaults here fit
// the panel alone, and a real deployment raises them per server. Their listening
// ports (25565 and up, 19132/udp for Bedrock) are not published by this workload:
// which ports exist is decided in the panel at runtime, so add them with
// kurly.extraPort once you know.
//
// Single writer: the panel keeps its SQLite database, the server directories and
// the backups on ReadWriteOnce volumes, so one replica, recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='crafty-controller',
  image=defaultImage,
  // The panel's own state: config.json, the TLS certificate it generates, and the
  // SQLite database holding the accounts and the server inventory.
  configSize='1Gi',
  // The Minecraft servers themselves — jars, worlds, mods. This is the one that
  // grows.
  serversSize='20Gi',
  // Where the panel writes the archives its scheduled backups produce.
  backupsSize='20Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '250m', memory: '1Gi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8443)
  + kurly.servicePort(8443)
  + (if env == {} then {} else kurly.env(env))
  // The launcher takes the non-root path it documents for Kubernetes: it execs the
  // panel directly instead of sudo-ing to the crafty account, so no privilege drop
  // is needed. The image's own uid, with the root GROUP the image gives every file
  // group-write on, and fsGroup so the empty volumes arrive writable too.
  + kurly.runAs(1000, 0, 0)
  // The panel refuses to start unless its working directory is writable, and it
  // keeps logs, migration markers and the venv's bytecode inside the image tree.
  + kurly.writableRootFilesystem()
  + kurly.store('/crafty/app/config', configSize, storageClass=storageClass)
  + kurly.store('/crafty/servers', serversSize, storageClass=storageClass)
  + kurly.store('/crafty/backups', backupsSize, storageClass=storageClass)
  // First boot lays down the default config, generates a certificate and creates
  // the database before anything listens.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 60, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
