// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// atomic-server — an AtomicServer instance (a graph database with documents,
// collections, full-text search and a browser UI, all in one static binary). A
// plain composable kurly.http workload: the store, the uploads and the search
// index live on one PersistentVolume, so it needs nothing external. Import it and
// render with kurly.list:
//
//   local atomicServer = import 'github.com/metio/kurly/workloads/atomic-server/server.libsonnet';
//   kurly.list(atomicServer())
//
// Serves on :9883 — compose an exposure onto it.
//
// THE PORT IS MOVED OFF THE IMAGE'S DEFAULT. The image sets ATOMIC_PORT=80, which
// only a process holding NET_BIND_SERVICE may bind; the binary is upstream's own
// default port instead, so the pod keeps the restricted posture and binds as an
// ordinary user.
//
// SET serverUrl BEFORE ANYBODY WRITES DATA. Every resource AtomicServer stores is
// identified by an absolute URL derived from this value, so changing it later does
// not rename the existing resources — it leaves them addressed under a hostname
// that no longer serves them. Unset, the server calls itself
// `http://localhost:9883`, which is right for a smoke test and wrong for anything
// reachable.
//
// The first visitor to /setup becomes the root agent, and until somebody goes
// there the invite is unclaimed: on an exposed instance that is whoever arrives
// first. Claim it immediately after the first deploy, or expose it only once you
// have.
//
// Single writer: one embedded store on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) — two servers on one store is not something the store
// sorts out afterwards.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='atomic-server',
  image=defaultImage,
  port=9883,
  serverUrl=null,
  storageSize='10Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(port)
  + kurly.servicePort(port)
  + kurly.env(
    {
      // The image points both directories inside its declared volume; the store
      // below is mounted there, so the defaults are kept and only stated again so
      // a reader can see where the data goes.
      ATOMIC_DATA_DIR: '/atomic-storage/data',
      ATOMIC_CONFIG_DIR: '/atomic-storage/config',
      ATOMIC_PORT: std.toString(port),
      // Every interface: a pod that binds one address is a pod nothing outside it
      // can reach.
      ATOMIC_IP: '0.0.0.0',
    }
    + (if serverUrl == null then {} else { ATOMIC_SERVER_URL: serverUrl })
    + env
  )
  // The image declares no user and carries no account database, so a uid is
  // stated here: the restricted default demands a non-root one and the image
  // cannot supply it. fsGroup is what makes the volume writable for it.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // A Service named after the workload makes Kubernetes inject ATOMIC_SERVER_PORT
  // as a tcp:// URL, which the binary parses as its own port setting and refuses.
  + kurly.disableServiceLinks()
  // The binary writes temporary files while indexing and while accepting uploads.
  + kurly.scratch('/tmp')
  + kurly.store('/atomic-storage', storageSize, storageClass=storageClass)
  // Probed by connection: the browser app answers on paths that redirect, and
  // reads are authenticated unless the instance is put in public mode, so a path
  // probe would report a healthy server as failed.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  // A first start populates the store and builds the search index before it
  // listens, which is minutes on a slow volume.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 30 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
