// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// openbao — an identity-based secrets and encryption manager (the community fork
// of Vault). A plain composable kurly.http workload: the default storage backend
// is the file backend on a PersistentVolume, so a single node needs no external
// database. Import it and render with kurly.list:
//
//   local openbao = import 'github.com/metio/kurly/workloads/openbao/server.libsonnet';
//   kurly.list(openbao())
//
// Serves the API and UI on :8200 — compose an exposure onto it.
//
// IT STARTS SEALED, AND THAT IS THE POINT. A fresh server has no root key and no
// unseal keys until somebody runs `bao operator init`, and it seals again on
// every restart until somebody unseals it. So the probes here are TCP: an HTTP
// health check reports 501 uninitialised and 503 sealed, and a liveness probe
// reading those would restart a server that is behaving exactly as designed,
// forever. Expect to unseal after a rollout.
//
// TLS: `tls_disable` is set, because a cluster deployment terminates TLS at the
// exposure in front of it and OpenBao would otherwise want a certificate before
// it will answer at all. Traffic between the pod and that exposure is plaintext
// inside the cluster — compose a service mesh onto this if that is not
// acceptable, or pass a listener of your own through `config`.
//
// MEMORY LOCKING: `disable_mlock` is set, so the process does not need the
// IPC_LOCK capability the hardened default drops. The trade is that secrets in
// memory may be swapped to disk — on a node with swap off, which is what
// Kubernetes has historically required, there is nothing to swap to.
//
// Single writer: the file backend is one directory on a ReadWriteOnce volume, so
// one replica, recreated (never rolled). Raft (`storage "raft"` through `config`,
// on a stateful set) is what more than one node needs.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='openbao',
  image=defaultImage,
  storageSize='5Gi',
  storageClass=null,
  // The address clients and other nodes reach this server at; OpenBao redirects
  // to it, so a wrong value shows up as a client following a link to nowhere.
  apiAddr=null,
  // Merged over the rendered config.hcl — any of OpenBao's own configuration.
  config={},
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8200)
  + kurly.servicePort(8200)
  + kurly.args(['server', '-config=/openbao/config/config.json'])
  // The uid the image's own openbao user carries; fsGroup so the file backend's
  // directory is writable.
  + kurly.runAs(100, gid=1000, fsGroup=1000)
  + kurly.store('/openbao/file', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.config({
    'config.json': std.manifestJsonEx({
      ui: true,
      disable_mlock: true,
      listener: { tcp: { address: '0.0.0.0:8200', tls_disable: true } },
      storage: { file: { path: '/openbao/file' } },
    } + (if apiAddr != null then { api_addr: apiAddr } else {}) + config, '  '),
  }, mountPath='/openbao/config')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
