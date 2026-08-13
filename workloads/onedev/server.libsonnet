// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// onedev — a self-contained DevOps platform: Git hosting, code search, pull
// requests, issues and a CI/CD engine in one server. A plain composable
// kurly.http workload: repositories, attachments and — by default — the database
// itself live under /opt/onedev on a PersistentVolume, so nothing else is needed
// to run it. Import it and render with kurly.list:
//
//   local onedev = import 'github.com/metio/kurly/workloads/onedev/server.libsonnet';
//   kurly.list(onedev())
//
// Serves the web UI and API on :6610 and Git-over-SSH on :6611 — compose an
// exposure onto the HTTP port, and route the SSH port separately if clones over
// SSH are wanted.
//
// IT INSTALLS ITSELF INTO THE VOLUME, AS ROOT. The image's entrypoint copies and
// upgrades the application tree into /opt/onedev on every start and then runs the
// Java service wrapper, which manages its own child process. Both want to own
// that tree, so this stage relaxes two defaults deliberately: it runs as root,
// and it allows the privilege escalation the wrapper needs. The root filesystem
// stays read-only — everything written goes to the volume or a scratch mount —
// and nothing else about the hardened posture is given up.
//
// BUILDS RUN SOMEWHERE. The server can execute CI jobs in its own container,
// which means a job can do whatever this pod can do. A OneDev used for CI should
// point at a Kubernetes executor instead, so jobs run as their own pods with
// their own limits.
//
// Single writer: the embedded database and the repositories are one directory on
// a ReadWriteOnce volume, so one replica, recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='onedev',
  image=defaultImage,
  storageSize='50Gi',
  storageClass=null,
  // An external database, e.g. jdbc:postgresql://onedev-db-rw:5432/onedev. Left
  // null OneDev keeps its embedded HSQLDB inside the volume, which is fine for a
  // small instance and is not what a busy one wants.
  dbUrl=null,
  dbUser=null,
  // A Secret carrying hibernate_connection_password when dbUrl is set.
  secretName='onedev',
  env={},
  resources={ requests: { cpu: '500m', memory: '2Gi' }, limits: { memory: '4Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(6610)
  + kurly.servicePort(6610)
  + kurly.extraPort('ssh', 6611)
  + kurly.env(
    { initial_ssh_root_url: 'ssh://' + name + ':6611' }
    + (if dbUrl != null then { hibernate_connection_url: dbUrl } else {})
    + (if dbUser != null then { hibernate_connection_username: dbUser } else {})
    + env
  )
  // The entrypoint installs into /opt/onedev and the service wrapper forks its
  // own child, so root and the escalation the wrapper performs are both needed.
  // See the header: the read-only root filesystem stays.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.store('/opt/onedev', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '1Gi')
  + (if secretName != null then kurly.envFromSecret(secretName) else {})
  // The first request lands on a setup wizard and the JVM takes a while to get
  // there, so the readiness gate is a connection and the startup budget is
  // generous rather than a path that does not answer yet.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 60 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
