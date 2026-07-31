// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// inspircd — an InspIRCd server (a modular IRC daemon). A plain composable
// kurly.http workload on the official image: it keeps its runtime data (logs, TLS
// material) on a PersistentVolume and reads its configuration from a mounted
// config. Import it and render with kurly.list:
//
//   local inspircd = import 'github.com/metio/kurly/workloads/inspircd/server.libsonnet';
//   kurly.list(inspircd())
//
// Serves IRC-over-TLS on :6697 — route it as TCP through a LoadBalancer or Gateway
// TCPRoute.
//
// CONFIGURATION: InspIRCd needs its configuration at /inspircd/conf (an
// inspircd.conf and the files it includes). Mount it with kurly.config, or from a
// Secret (kurly mints none) where it carries oper passwords or link credentials.
//
// Single writer: the runtime data lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='inspircd',
  image=defaultImage,
  storageSize='1Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(6697)
  + kurly.servicePort(6697)
  + (if env == {} then {} else kurly.env(env))
  // The image insists on uid 10000 and says so itself when it is not: "Can't
  // write to volume! Please change owner to uid 10000". At any other uid the
  // entrypoint cannot write the volume and the server never starts.
  + kurly.runAs(10000, gid=10000, fsGroup=10000)
  + kurly.store('/inspircd/data', storageSize, storageClass=storageClass)
  // The entrypoint generates a TLS key and a default configuration on first boot,
  // and writes both beside the installation rather than into the data volume:
  // /tmp/cert.template, then /inspircd/conf/key.pem. Against the read-only root
  // filesystem kurly ships by default it fails on each in turn and exits with
  // "Cannot open config file: /inspircd/conf/inspircd.conf" — which reads like a
  // missing config and is really a filesystem it could not write one to.
  //
  // Scratch rather than a relaxed root filesystem: only these two paths need to
  // be writable, and a self-signed key regenerated per start is the right
  // lifetime for one the container makes itself.
  + kurly.scratch('/tmp', '16Mi')
  + kurly.scratch('/inspircd/conf', '16Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
