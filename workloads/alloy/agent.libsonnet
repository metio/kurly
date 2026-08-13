// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// alloy — Grafana's OpenTelemetry collector distribution: it scrapes metrics,
// tails logs and receives traces, then forwards them to whatever stores them. A
// composable kurly.daemon workload, because collecting a node's logs means being
// on that node. Import it and render with kurly.list:
//
//   local alloy = import 'github.com/metio/kurly/workloads/alloy/agent.libsonnet';
//   kurly.list(alloy(namespace='alloy', config=|||
//     prometheus.remote_write "default" {
//       endpoint { url = "http://mimir:9009/api/v1/push" }
//     }
//   |||))
//
// ALLOY SHIPS DATA SOMEWHERE ELSE; IT STORES NOTHING. It is the collector half of
// an observability stack, so a deployment needs a backend for the metrics, logs
// or traces it forwards — and kurly carries Prometheus, Loki, Tempo and Thanos
// for exactly that. An Alloy with no destination configured runs happily and
// drops everything.
//
// THE CONFIGURATION IS A PROGRAM, NOT A DOCUMENT. Alloy's config is written in
// its own language, with components wired to each other by reference; there is no
// useful default beyond a self-monitoring skeleton, so `config` takes that
// language verbatim rather than pretending a YAML shape underneath.
//
// IT ASKS THE APISERVER WHAT TO SCRAPE. Discovering pods, services and endpoints
// across the cluster is what makes it a collector rather than a static scraper,
// so the grant is cluster-wide and read-only.
//
// THE STORAGE PATH IS A WAL, NOT A DATABASE. Alloy buffers what it has not yet
// delivered under its storage path; on the pod that survives a container restart
// and not a reschedule, which for a metrics agent means a gap rather than a loss
// of record.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './agent.image', '\n');

function(
  name='alloy',
  image=defaultImage,
  // The namespace this is deployed into; the ClusterRoleBinding's subject needs
  // it, and one without a namespace grants nothing.
  namespace='alloy',
  // Alloy's own configuration language, verbatim. The default watches nothing but
  // itself.
  config=|||
    logging {
      level  = "info"
      format = "logfmt"
    }
  |||,
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  env={},
  labels={},
  annotations={},
)
  kurly.daemon(name, image)
  + kurly.version(version)
  + kurly.port(12345)
  + kurly.env(env)
  + kurly.command(['/bin/alloy'])
  // Bound to every interface because the kubelet's probe is a request from
  // outside the pod's loopback. THE UI THAT ANSWERS THERE SHOWS THE COMPONENT
  // GRAPH AND THE VALUES FLOWING THROUGH IT — a daemon publishes no Service, so
  // nothing reaches it by default, and adding one publishes whatever the
  // pipelines carry.
  + kurly.args(['run', '/etc/alloy/config.alloy', '--storage.path=/var/lib/alloy/data', '--server.http.listen-addr=0.0.0.0:12345'])
  + kurly.config({ 'config.alloy': config }, mountPath='/etc/alloy')
  // Discovering what to scrape: pods, services, endpoints and nodes, everywhere.
  + kurly.clusterRbac(
    [
      { apiGroups: [''], resources: ['nodes', 'nodes/proxy', 'nodes/metrics', 'services', 'endpoints', 'pods'], verbs: ['get', 'list', 'watch'] },
      { apiGroups: ['discovery.k8s.io'], resources: ['endpointslices'], verbs: ['get', 'list', 'watch'] },
      { apiGroups: ['networking.k8s.io'], resources: ['ingresses'], verbs: ['get', 'list', 'watch'] },
      { nonResourceURLs: ['/metrics', '/metrics/cadvisor'], verbs: ['get'] },
    ],
    namespace=namespace
  )
  // The undelivered-data buffer, and the node's container logs for the pipelines
  // that tail them. Read-only: an agent that could write the logs could rewrite
  // the record it exists to ship.
  // The whole state directory, not just data/ below it: the remotecfg service
  // creates its own directories beside data/, and a read-only parent refuses that
  // even to root.
  + kurly.scratch('/var/lib/alloy', '2Gi')
  + kurly.hostPath('/var/log', type='Directory')
  + kurly.scratch('/tmp', '256Mi')
  // The image runs as root; reading another container's logs off the node needs a
  // uid that may.
  + kurly.rootUser()
  + kurly.readinessProbe({ httpGet: { path: '/-/ready', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
