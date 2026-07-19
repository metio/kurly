// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// bigcapital-gateway — the Bigcapital edge (an nginx reverse proxy). It is the
// entry point: it routes the browser to the webapp and /api to the server. This is
// the one Bigcapital stage you expose. One of three coordinated stages — see the
// server stage's header and the workload README.
//
//   local gateway = import 'github.com/metio/kurly/workloads/bigcapital/gateway.libsonnet';
//   kurly.list(gateway())
//
// Serves on :80 — compose an exposure onto it. It reaches the server and webapp by
// their Service names (derived from namePrefix).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  namePrefix='bigcapital',
  name=null,
  image='docker.io/bigcapitalhq/gateway:v0.25.23',
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  local resolvedName = if name != null then name else namePrefix + '-gateway';
  local baseEnv = {
    SERVER_HOST: namePrefix + '-server',
    SERVER_PORT: '4000',
    WEBAPP_HOST: namePrefix + '-webapp',
    WEBAPP_PORT: '80',
  };

  kurly.http(resolvedName, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env(baseEnv + env)
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
