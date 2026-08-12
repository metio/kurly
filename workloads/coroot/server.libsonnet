// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// coroot — an observability platform that builds a service map from eBPF
// telemetry and turns it into answers about latency, errors and cost, without
// instrumenting the applications. A composable kurly.http workload: its own
// configuration and cache live on a PersistentVolume, the metrics in Prometheus
// and the traces, logs and profiles in ClickHouse. Import it and render with
// kurly.list:
//
//   local coroot = import 'github.com/metio/kurly/workloads/coroot/server.libsonnet';
//   kurly.list(coroot(prometheusUrl='http://prometheus:9090', clickhouseAddress='clickhouse:9000'))
//
// Serves the web app on :8080 — compose an exposure onto it.
//
// THE SERVER SEES NOTHING ON ITS OWN. Every measurement comes from the node-agent
// stage, one per node, which is where the privilege and the eBPF live. A Coroot
// with no agents starts, serves an empty service map, and reports no error worth
// noticing — deploy both.
//
// TWO DEPENDENCIES, DIFFERENT JOBS. Prometheus holds the metrics and ClickHouse
// the traces, logs and profiles; Coroot bootstraps its own configuration to point
// at both on first start. Neither is optional in a deployment that shows
// anything, and kurly carries neither: ClickHouse is not in this catalogue,
// because its authors sell hosting for it.
//
// Single writer: one data directory on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='coroot',
  image=defaultImage,
  storageSize='10Gi',
  storageClass=null,
  // The Prometheus holding the metrics the agents write.
  prometheusUrl=null,
  // host:port of the ClickHouse holding traces, logs and profiles.
  clickhouseAddress=null,
  clickhouseUser='default',
  clickhouseDatabase='default',
  // A Secret carrying BOOTSTRAP_CLICKHOUSE_PASSWORD.
  secretName=null,
  // How often Coroot refreshes what it discovered on bootstrap.
  refreshInterval='15s',
  extraArgs=[],
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.args(
    ['--listen=:8080', '--data-dir=/data']
    + (if prometheusUrl != null then ['--bootstrap-prometheus-url=' + prometheusUrl, '--bootstrap-refresh-interval=' + refreshInterval] else [])
    + extraArgs
  )
  + kurly.env(
    (if clickhouseAddress != null then {
       BOOTSTRAP_CLICKHOUSE_ADDRESS: clickhouseAddress,
       BOOTSTRAP_CLICKHOUSE_USER: clickhouseUser,
       BOOTSTRAP_CLICKHOUSE_DATABASE: clickhouseDatabase,
     } else {})
    + env
  )
  // The uid the image already runs as; fsGroup makes the data directory writable.
  + kurly.runAs(65534, gid=65534, fsGroup=65534)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '256Mi')
  + (if secretName != null then kurly.envFromSecret(secretName) else {})
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
