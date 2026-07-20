// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// registry — a Docker Registry server (the reference implementation of the OCI registry: a
// self-hosted store and distribution point for container images). A plain composable kurly.http
// workload on the official image; its stored images live on a PersistentVolume. Import it and
// render with kurly.list:
//
//   local registry = import 'github.com/metio/kurly/workloads/registry/server.libsonnet';
//   kurly.list(registry())
//
// Serves the registry API on :5000 — usually reached in-cluster (registry:5000); the
// docker-registry-ui workload gives it a browsable web interface.
//
// AUTH & TLS: the bare registry is unauthenticated and plaintext. Front it with TLS and put
// basic-auth or a token service in front (REGISTRY_AUTH_*), or run it only inside the cluster.
//
// Single writer: the images live on a ReadWriteOnce volume, so one replica, recreated. For a
// scaled, HA registry, back it with S3 or another shared storage driver instead.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='registry',
  image='docker.io/library/registry:2.8.3',
  storageSize='50Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(5000)
  + kurly.servicePort(5000)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/var/lib/registry', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
