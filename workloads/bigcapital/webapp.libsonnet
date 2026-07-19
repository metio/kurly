// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// bigcapital-webapp — the Bigcapital front end (the single-page web app). A
// stateless kurly.http workload on the official image; the gateway proxies to it.
// One of three coordinated Bigcapital stages — see the server stage's header and
// the workload README.
//
//   local webapp = import 'github.com/metio/kurly/workloads/bigcapital/webapp.libsonnet';
//   kurly.list(webapp())
//
// Serves the web app on :80. Stateless, so it can run several replicas.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  namePrefix='bigcapital',
  name=null,
  image='docker.io/bigcapitalhq/webapp:v0.25.23',
  replicas=1,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  local resolvedName = if name != null then name else namePrefix + '-webapp';

  kurly.http(resolvedName, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(80)
  + kurly.servicePort(80)
  + (if env == {} then {} else kurly.env(env))
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
