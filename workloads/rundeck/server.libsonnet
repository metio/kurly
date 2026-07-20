// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// rundeck — a Rundeck server (a self-hosted runbook-automation and operations platform:
// define jobs and workflows and run them across your nodes with access control and
// scheduling). A plain composable kurly.http workload on the official image; with the default
// embedded storage its data lives on a PersistentVolume. Import it, adapt with the parameters
// below, and render with kurly.list:
//
//   local rundeck = import 'github.com/metio/kurly/workloads/rundeck/server.libsonnet';
//   kurly.list(rundeck(grailsUrl='https://rundeck.example.com'))
//
// Serves the web app and API on :4440 — compose an exposure onto it.
//
// URL & SECRETS: Rundeck builds absolute links from RUNDECK_GRAILS_URL and needs its admin
// credentials. kurly authors no Secret; provide one holding them, pulled in via envFrom.
// Point it at an external MySQL/PostgreSQL (the RUNDECK_DATABASE_* env) to scale past the
// embedded database.
//
// Single writer: the data lives on a ReadWriteOnce volume, so one replica, recreated (never
// rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='rundeck',
  image='docker.io/rundeck/rundeck:5.9.0',
  storageSize='10Gi',
  storageClass=null,
  grailsUrl=null,
  secretName='rundeck-secrets',
  env={},
  resources={ requests: { cpu: '250m', memory: '1Gi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = if grailsUrl == null then {} else { RUNDECK_GRAILS_URL: grailsUrl };
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(4440)
  + kurly.servicePort(4440)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/home/rundeck/server/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
