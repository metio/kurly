// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// thanos query-frontend — an OPTIONAL performance layer in front of thanos query:
// it splits long-range queries into smaller parallel ones, caches the results,
// and retries transient failures, then forwards to a downstream Querier. Like
// query it is a plain `thanos query-frontend` Deployment (not an operator custom
// resource), so it is an ordinary composable kurly.http workload. It owns no data
// — the result cache is in-memory by default. Import it, point it at a Querier,
// and render with kurly.list:
//
//   local frontend = import 'github.com/metio/kurly/workloads/thanos/query-frontend.libsonnet';
//   kurly.list(frontend(downstreamUrl='http://thanos-query.monitoring.svc:10902'))
//
// It serves the same Prometheus-compatible API as query on :10902, so a Grafana
// datasource points here instead of directly at the Querier. For a shared cache
// across replicas, pass a --query-range.response-cache-config-file through
// extraArgs and mount it with kurly.config, backed by the memcached or valkey
// workload; the default in-memory cache needs no wiring.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// The workload version, stamped as app.kubernetes.io/version; the release
// pipeline overwrites version.txt with the calver.
local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='thanos-query-frontend',
  image='quay.io/thanos/thanos:v0.42.2',
  replicas=2,
  // The Querier this frontend forwards to. Defaults to a `thanos-query` Service on
  // :10902 in the same namespace — the query workload's own default name.
  downstreamUrl='http://thanos-query:10902',
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
  // Extra `thanos query-frontend` flags passed verbatim (--query-range.split-interval,
  // --query-range.response-cache-config-file, --labels.split-interval, …).
  extraArgs=[],
)
  local args =
    [
      'query-frontend',
      '--http-address=0.0.0.0:10902',
      '--query-frontend.downstream-url=' + downstreamUrl,
    ]
    + extraArgs;

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(10902)
  + kurly.servicePort(10902)
  + kurly.args(args)
  // The thanos image ships no non-root user, and the restricted default demands
  // one; the frontend is stateless (in-memory cache), so read-only rootfs stands.
  + kurly.runAs(1001)
  + kurly.readinessProbe({ httpGet: { path: '/-/ready', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/-/healthy', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
