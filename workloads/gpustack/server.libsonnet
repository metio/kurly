// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// gpustack/server — the control plane of a GPU cluster: it holds the model
// catalogue, schedules inference onto workers and serves an OpenAI-compatible API
// in front of whatever they are running. A plain composable kurly.http workload.
// Import it and render with kurly.list:
//
//   local gpustack = import 'github.com/metio/kurly/workloads/gpustack/server.libsonnet';
//   kurly.list(gpustack())
//
// Serves the interface and the inference API on :80 — compose an exposure onto it.
//
// THE SERVER NEEDS NO GPU AND THE WORKERS ARE NOT THIS. A worker is where a model
// actually runs, and upstream starts one with --privileged, the host's network,
// the host's Docker socket and the NVIDIA runtime — a set of privileges this
// recipe deliberately does not package, because a workload that asks for all four
// is a node agent rather than a tenant's deployment. Run the server here and join
// workers to it with the token below.
//
// THE BOOTSTRAP PASSWORD AND THE JOIN TOKEN ARE GENERATED ONTO THE VOLUME. On the
// first start the server writes an initial admin password and a worker token
// under /var/lib/gpustack, so a deployment that does not read them out of the
// volume cannot log in or join anything.
//
// Single writer: the database and the model cache live on one ReadWriteOnce
// volume, so one replica, recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='gpustack',
  image=defaultImage,
  storageSize='100Gi',
  storageClass=null,
  extraArgs=[],
  env={},
  resources={ requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '4Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env(env)
  + (if extraArgs == [] then {} else kurly.args(extraArgs))
  // THE IMAGE IS AN s6-overlay SUPERVISION TREE: it raises its own file-descriptor
  // limit, writes its runtime configuration under /run/gpustack and starts several
  // services under their own users. None of that works from an unprivileged uid
  // with capabilities dropped and a read-only root filesystem.
  + kurly.runAs(0, gid=0)
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  + kurly.writableRootFilesystem()
  + kurly.store('/var/lib/gpustack', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '1Gi')
  // The first start initialises a database and downloads nothing yet, but the
  // supervision tree takes its time coming up, so the wait is a startup probe.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 60 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
