// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// jaeger — distributed tracing: it receives spans over OTLP, stores them and
// serves the UI that reconstructs a request's path through a system. A plain
// composable kurly.http workload running the Jaeger v2 binary with its built-in
// all-in-one configuration. Import it and render with kurly.list:
//
//   local jaeger = import 'github.com/metio/kurly/workloads/jaeger/server.libsonnet';
//   kurly.list(jaeger())
//
// Serves the UI on :16686 and accepts OTLP on :4317 (gRPC) and :4318 (HTTP) —
// compose an exposure onto the UI, and point instrumented workloads at the
// Service's OTLP ports.
//
// TRACES ARE IN MEMORY AND THEY DO NOT SURVIVE A RESTART. The shipped
// configuration keeps spans in a bounded in-process store, which is what makes
// this one container with no dependencies — and it means a rollout, an eviction
// or an OOM kill loses everything collected so far. That is a fair trade for
// development and for debugging a staging cluster, and it is not a trace archive.
// Anything that has to keep traces needs a storage backend (Elasticsearch,
// OpenSearch, Cassandra, or the badger file store) configured through `config`,
// with the volume or the backend to go with it.
//
// Stateless BY CONSEQUENCE, not by design: with the memory store any replica
// count is legal, but each pod holds its own traces, so a query answered by one
// pod cannot see spans the other received. One replica is the arrangement that
// answers questions correctly.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='jaeger',
  image=defaultImage,
  // A Jaeger v2 (OpenTelemetry Collector) configuration, rendered as a ConfigMap
  // and passed with --config. Null leaves the image's built-in all-in-one
  // configuration in place.
  config=null,
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(16686)
  + kurly.servicePort(16686)
  + kurly.extraPort('otlp-grpc', 4317)
  + kurly.extraPort('otlp-http', 4318)
  // The collector's own health endpoint, which the probes read.
  + kurly.extraPort('health', 13133, expose=false)
  + kurly.env({ JAEGER_LISTEN_HOST: '0.0.0.0' } + env)
  // The uid the image already runs as.
  + kurly.runAs(10001, gid=10001)
  + kurly.scratch('/tmp', '64Mi')
  + (if config != null then
       kurly.args(['--config', '/etc/jaeger/config.yaml'])
       + kurly.config({ 'config.yaml': std.manifestYamlDoc(config, quote_keys=false) }, mountPath='/etc/jaeger')
     else {})
  + kurly.readinessProbe({ httpGet: { path: '/status', port: 'health' } })
  + kurly.livenessProbe({ httpGet: { path: '/status', port: 'health' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
