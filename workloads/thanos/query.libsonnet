// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// thanos query — the Thanos Querier: a stateless component that implements the
// Prometheus HTTP API by fanning out to StoreAPI endpoints (Prometheus sidecars,
// store gateways, rulers, receivers), deduplicating replicas, and merging the
// results into one global view. Unlike the ruler, this is not a
// prometheus-operator custom resource — it is a plain `thanos query` Deployment,
// so it is an ordinary composable kurly.http workload. Import it, adapt with `+`
// features, and render with kurly.list:
//
//   local query = import 'github.com/metio/kurly/workloads/thanos/query.libsonnet';
//   kurly.list(query(endpoints=[
//     'dnssrv+_grpc._tcp.prometheus-operated.monitoring.svc.cluster.local',
//     'dnssrv+_grpc._tcp.thanos-store.monitoring.svc.cluster.local',
//   ]))
//
// Reach the Prometheus-compatible API at the Service on :10902 — point a Grafana
// datasource, or the thanos query-frontend, at it. The pod also serves the
// StoreAPI over gRPC on :10901 for a higher-level Querier to federate; expose
// that with the raw `+` escape if you nest queriers.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// The workload version, stamped as app.kubernetes.io/version; the release
// pipeline overwrites version.txt with the calver.
local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='thanos-query',
  image='quay.io/thanos/thanos:v0.42.2',
  replicas=2,
  // The StoreAPI endpoints to fan out to (gRPC). Each becomes a --endpoint flag;
  // the `dnssrv+` prefix resolves an SRV record so every backing replica is used.
  endpoints=[],
  // Labels that distinguish replicas of the same data (HA Prometheus pairs, Thanos
  // Receive replication), so the Querier deduplicates across them. The defaults
  // match prometheus-operator (`prometheus_replica`) and Thanos Receive/sidecar
  // (`replica`); set [] to disable deduplication.
  queryReplicaLabels=['prometheus_replica', 'replica'],
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
  // Extra `thanos query` flags passed verbatim (--query.auto-downsampling,
  // --query.timeout, --endpoint-strict, …).
  extraArgs=[],
)
  local args =
    [
      'query',
      '--http-address=0.0.0.0:10902',
      '--grpc-address=0.0.0.0:10901',
    ]
    + ['--endpoint=' + endpoint for endpoint in endpoints]
    + ['--query.replica-label=' + label for label in queryReplicaLabels]
    + extraArgs;

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(10902)
  + kurly.servicePort(10902)
  + kurly.args(args)
  // The thanos image ships no non-root user, and the restricted default demands
  // one; the querier is stateless, so the read-only root filesystem stands.
  + kurly.runAs(1001)
  // Readiness gates traffic until the StoreAPIs are discovered; liveness only
  // restarts a wedged process, so it must NOT ride /-/ready (a querier with its
  // endpoints briefly down is unready, not dead).
  + kurly.readinessProbe({ httpGet: { path: '/-/ready', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/-/healthy', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
