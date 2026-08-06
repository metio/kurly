// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// quickshare — a Quickshare server (simple file sharing between devices through a
// web interface: upload, browse and hand out share links). A plain composable
// kurly.http workload: the shared files and the SQLite database that indexes them
// live together on a PersistentVolume, so it needs nothing external. Import it and
// render with kurly.list:
//
//   local quickshare = import 'github.com/metio/kurly/workloads/quickshare/server.libsonnet';
//   kurly.list(quickshare())
//
// Serves the web UI and API on :8686 — compose an exposure onto it.
//
// Single writer: one SQLite database and one file tree on a ReadWriteOnce volume,
// so one replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='quickshare',
  image=defaultImage,
  storageSize='10Gi',
  storageClass=null,
  // The Secret holding DEFAULTADMIN and DEFAULTADMINPWD — the administrator
  // Quickshare creates on its FIRST start. Without them it invents a password and
  // prints it to the log once, which is nobody's idea of a credential. kurly mints
  // no Secret.
  secretName='quickshare',
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8686)
  + kurly.servicePort(8686)
  + (if env == {} then {} else kurly.env(env))
  + kurly.envFromSecret(secretName)
  // A static Go binary reading its configuration from /quickshare/docker.yml, which
  // puts both the file tree and the SQLite database under /quickshare/root. The
  // image's own tree is group-owned by 8686 and mode 0770, so run as that uid/gid
  // and give the volume the same fsGroup.
  + kurly.runAs(8686, gid=8686, fsGroup=8686)
  + kurly.store('/quickshare/root', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '64Mi')
  // The Service is named after the workload, so Kubernetes would inject
  // QUICKSHARE_PORT as a tcp:// URL into an application that reads its own settings
  // from the environment.
  + kurly.disableServiceLinks()
  // Probe by connection: the web UI answers on / but the API paths want a session,
  // and a probe that authenticates is a probe that can lock the pod out.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
