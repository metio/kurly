// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// domoticz — a Domoticz server (a home-automation system that monitors and configures
// switches, sensors, meters and weather devices, with its own event engine and dashboard).
// A plain composable kurly.http workload on the official image; its database, scripts and
// plugins live on a PersistentVolume. Import it and render with kurly.list:
//
//   local domoticz = import 'github.com/metio/kurly/workloads/domoticz/server.libsonnet';
//   kurly.list(domoticz())
//
// Serves the dashboard on :8080 — compose an exposure onto it.
//
// The entrypoint runs as root: it rsyncs the bundled plugin, template and dzVents examples
// onto the volume, chowns the whole userdata tree, and touches a marker beside the
// application, so this relaxes the non-root and read-only-rootfs defaults and grants back
// the two capabilities the chown needs. Local-network device discovery (broadcast, USB
// radios) does not work through a ClusterIP; devices reachable by IP or MQTT do.
//
// Single writer: the database lives on a ReadWriteOnce volume, so one replica, recreated
// (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='domoticz',
  image=defaultImage,
  storageSize='5Gi',
  storageClass=null,
  // The timezone the event engine and the logs use.
  timezone='Etc/UTC',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    TZ: timezone,
    WWW_PORT: '8080',
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  // The entrypoint passes -www $WWW_PORT, so the declared port and WWW_PORT move together.
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env(baseEnv + env)
  // The entrypoint chowns the userdata tree and marks the container configured beside the
  // application, both as root.
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  // Everything is dropped and these are granted back by name — what the recursive chown
  // over the volume needs, and nothing else.
  + kurly.addCapabilities(['CHOWN', 'FOWNER'])
  + kurly.store('/opt/domoticz/userdata', storageSize, storageClass=storageClass)
  // The self-repair rsync and the first-run database creation happen before anything
  // listens.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 30 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
