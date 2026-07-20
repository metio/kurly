// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// jenkins — a Jenkins controller (the self-hosted automation server for building, testing and
// deploying software). A plain composable kurly.http workload on the official LTS image; its home
// directory (jobs, plugins, config, build history) lives on a PersistentVolume. Import it and
// render with kurly.list:
//
//   local jenkins = import 'github.com/metio/kurly/workloads/jenkins/server.libsonnet';
//   kurly.list(jenkins())
//
// Serves the web UI on :8080 — compose an exposure onto it. Inbound agents connect over the same
// HTTP port (websocket), so no extra Service port is needed for the common case.
//
// Single controller: JENKINS_HOME lives on a ReadWriteOnce volume, so one replica, recreated
// (never rolled) to keep two controllers off the same home directory.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='jenkins',
  image='docker.io/jenkins/jenkins:2.479.2-lts',
  storageSize='20Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/var/jenkins_home', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/login', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/login', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
