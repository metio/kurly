// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// ergo — an Ergo server (a modern IRCv3 daemon written in Go, with the account
// services, the bouncer and the message history other networks bolt on as separate
// programs built in). A plain composable kurly.http workload on the official image:
// its configuration, its database and its TLS material all live in /ircd on a
// PersistentVolume, so it needs nothing else. Import it and render with kurly.list:
//
//   local ergo = import 'github.com/metio/kurly/workloads/ergo/server.libsonnet';
//   kurly.list(ergo())
//
// Serves plaintext IRC on :6667 and IRC-over-TLS on :6697 — route both as TCP
// through a LoadBalancer or a Gateway TCPRoute; an HTTP exposure fits neither.
//
// FIRST BOOT WRITES THE CONFIGURATION AND KEEPS IT. The entrypoint copies the
// image's default configuration to /ircd/ircd.yaml only when that file is absent,
// prints a freshly generated admin oper password to the log as it does so, and then
// never touches it again — so read that password out of the first pod's log, and
// edit the file on the volume to change anything (a later image does not update
// it). The TLS certificate it makes itself is self-signed and regenerated only when
// missing; put a real one in place of /ircd/fullchain.pem and /ircd/privkey.pem for
// anything a client outside the cluster connects to.
//
// Single writer: one embedded database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) — two servers opening the same database is not something
// either of them will sort out afterwards.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='ergo',
  image=defaultImage,
  storageSize='5Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(6667)
  + kurly.servicePort(6667)
  + kurly.extraPort('ircs', 6697)
  + (if env == {} then {} else kurly.env(env))
  // The image declares no user and everything it does is ordinary: both ports are
  // above 1024, the binary lives in /ircd-bin and reads it, and the only thing it
  // writes is the volume — which fsGroup hands over.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // The whole state is one directory: ircd.yaml, ircd.db, and the self-signed
  // certificate pair beside them. It is also the working directory, which is what
  // makes the relative paths in the shipped configuration resolve here.
  + kurly.store('/ircd', storageSize, storageClass=storageClass)
  // The entrypoint builds the first configuration in /tmp (two awk passes and a
  // genpasswd run) before moving it onto the volume, so /tmp must be writable on
  // the very first start or nothing is ever generated.
  + kurly.scratch('/tmp', '16Mi')
  // Probe by connection: the IRC handshake is not something a probe speaks, and
  // the TLS port answers only after mkcerts has finished.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
