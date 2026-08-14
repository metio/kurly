// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// bifrost — an AI gateway: one OpenAI-compatible endpoint in front of many model
// providers, with failover, load balancing and per-key budgets, so an application
// holds one URL and one key instead of a provider's. A plain composable
// kurly.http workload on the project's own image. Import it and render with
// kurly.list:
//
//   local bifrost = import 'github.com/metio/kurly/workloads/bifrost/gateway.libsonnet';
//   kurly.list(bifrost(secretName='bifrost'))
//
// Serves the API and its web interface on :8080 — compose an exposure onto it.
//
// THE PROVIDER KEYS ARE THE WHOLE POINT AND THEY COME FROM A SECRET. A gateway
// with no upstream credential answers nothing, and those credentials are billed
// by the token: `secretName` names a Secret whose keys are the provider variables
// the configuration refers to (OPENAI_API_KEY, ANTHROPIC_API_KEY and the rest).
// kurly authors none of them.
//
// ANYBODY WHO REACHES IT CAN SPEND YOUR TOKENS. The gateway does not require a
// client key by default — governance, budgets and virtual keys are configured
// through its interface after the first start. Until that is done, treat reaching
// it as equivalent to holding every provider key it carries, and do not expose it
// to a network you do not control.
//
// Single writer: the configuration and the request logs live in one file database
// on a ReadWriteOnce volume, so one replica, recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './gateway.image', '\n');

function(
  name='bifrost',
  image=defaultImage,
  // A Secret carrying the provider API keys the configuration refers to.
  secretName=null,
  storageSize='10Gi',
  storageClass=null,
  logLevel='info',
  env={},
  resources={ requests: { cpu: '200m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  // APP_HOST is 0.0.0.0 in the image already; APP_DIR names the directory the
  // volume is mounted at, which is where the configuration and the logs go.
  + kurly.env({ APP_PORT: '8080', APP_DIR: '/app/data', LOG_LEVEL: logLevel } + env)
  // The uid the image already runs as, with fsGroup so the data directory is
  // writable by it.
  + kurly.runAs(1000, gid=0, fsGroup=1000)
  + kurly.store('/app/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '128Mi')
  + (if secretName != null then kurly.envFromSecret(secretName) else {})
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
