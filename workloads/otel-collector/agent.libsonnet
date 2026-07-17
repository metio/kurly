// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// otel-collector (agent) — an OpenTelemetry Collector as a per-node agent, the
// kurly.daemon shape: a DaemonSet running one collector on every node so local
// workloads send telemetry to a collector on their own node. Import it, adapt
// with the parameters below, and render with kurly.list:
//
//   local agent = import 'github.com/metio/kurly/workloads/otel-collector/agent.libsonnet';
//   kurly.list(agent(config=myPipelines))
//
// The collector's config is the whole workload — receivers, processors,
// exporters, and the service pipelines wiring them together. It is passed
// VERBATIM: `config` is the collector's own schema, which kurly does not model
// (a second-hand copy would drift against the collector's and lie about what it
// accepts), so it is rendered to the mounted config file as-is. The default is a
// working OTLP agent — receive OTLP, batch, and print — that a real deployment
// replaces by passing its own `config`, or builds on by extending this one.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// The workload version, stamped as app.kubernetes.io/version; the release
// pipeline overwrites version.txt with the calver.
local version = std.rstripChars(importstr './version.txt', '\n');

// A self-contained agent: accept OTLP over gRPC and HTTP, guard memory, batch,
// and export to the debug logger. It runs and is healthy out of the box, which
// makes it the sensible default and the smoke fixture; a real agent swaps the
// debug exporter for one that ships elsewhere (an OTLP gateway, a backend). The
// health_check extension backs the readiness/liveness probes below, so a config
// that drops it must move the probes too.
local defaultConfig = {
  extensions: { health_check: { endpoint: '0.0.0.0:13133' } },
  receivers: {
    otlp: { protocols: {
      grpc: { endpoint: '0.0.0.0:4317' },
      http: { endpoint: '0.0.0.0:4318' },
    } },
  },
  processors: {
    // memory_limiter first in every pipeline: it sheds load before the process
    // is OOMKilled against the container limit below, so a telemetry spike drops
    // data rather than the collector.
    memory_limiter: { check_interval: '1s', limit_percentage: 80, spike_limit_percentage: 25 },
    batch: {},
  },
  exporters: { debug: { verbosity: 'basic' } },
  service: {
    extensions: ['health_check'],
    pipelines: {
      traces: { receivers: ['otlp'], processors: ['memory_limiter', 'batch'], exporters: ['debug'] },
      metrics: { receivers: ['otlp'], processors: ['memory_limiter', 'batch'], exporters: ['debug'] },
      logs: { receivers: ['otlp'], processors: ['memory_limiter', 'batch'], exporters: ['debug'] },
    },
  },
};

function(
  name='otel-collector',
  image='docker.io/otel/opentelemetry-collector-contrib:0.119.0',
  config=defaultConfig,
)
  kurly.daemon(name, image)
  + kurly.version(version)
  // The contrib image runs as uid 10001, but pin it so runAsNonRoot always has a
  // numeric uid to admit against — a base image that ever dropped its USER would
  // otherwise fail the restricted default at admission rather than here.
  + kurly.runAs(10001)
  // Replaces the image's default `--config` (which points at its bundled sample)
  // with the mounted one below.
  + kurly.args(['--config=/etc/otel/config.yaml'])
  // The collector reads YAML; JSON is valid YAML, but manifestYamlDoc keeps the
  // rendered file readable when someone kubectl-gets the ConfigMap.
  + kurly.config({ 'config.yaml': std.manifestYamlDoc(config) }, mountPath='/etc/otel')
  // The collector speaks OTLP, not HTTP-on-the-data-port, so readiness is the
  // health_check extension's endpoint, not the OTLP port.
  + kurly.readinessProbe({ httpGet: { path: '/', port: 13133 } })
  + kurly.livenessProbe({ httpGet: { path: '/', port: 13133 } })
  // The memory limit is the ceiling memory_limiter shields; keep the two in the
  // same ballpark when tuning, so the processor sheds load before the kernel does.
  + kurly.resources(
    requests={ cpu: '100m', memory: '128Mi' },
    limits={ memory: '256Mi' },
  )
