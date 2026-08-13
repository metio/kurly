// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// kubetail/cluster-agent — the piece that reads log files off each node and
// streams them back to the cluster-api over gRPC. A composable kurly.daemon
// workload, because a node's log files are only readable from that node. Import
// it and render alongside the dashboard and the cluster-api.
//
// Speaks gRPC on :50051, and the cluster-api finds every agent through the
// headless Service this renders.
//
// IT READS THE NODE'S LOG DIRECTORY, WHICH IS EVERY CONTAINER'S OUTPUT. Mounted
// read-only: an agent that could write those files could alter the record it
// exists to serve. That is also why this is a cluster add-on rather than a tenant
// workload — what it can read is not scoped to a namespace.
//
// WHY A SEPARATE AGENT AT ALL, when the apiserver can serve pod logs: reading the
// files directly is what makes searching and following many pods at once cheap,
// instead of opening one apiserver stream per pod. The cost is a DaemonSet with a
// hostPath.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './cluster-agent.image', '\n');

function(
  name='kubetail-cluster-agent',
  image=defaultImage,
  port=50051,
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.daemon(name, image)
  + kurly.version(version)
  + kurly.port(port)
  + kurly.env(env)
  // The binary REQUIRES --config and exits with a usage message without one; the
  // environment variable alone configures nothing.
  + kurly.args(['--config', '/etc/kubetail/config.yaml'])
  + kurly.config({
    'config.yaml': std.manifestYamlDoc({
      // `tls` is not optional to the agent: it refuses to start with "missing
      // configuration field" rather than assuming a default. Off here, because
      // the certificate is the deployment's to supply.
      'cluster-agent': { addr: ':' + port, tls: { enabled: false } },
    }, quote_keys=false),
  }, mountPath='/etc/kubetail')
  // A DaemonSet publishes no Service of its own, and the cluster-api needs to
  // reach EVERY agent rather than one of them — a headless Service resolves to
  // all their addresses, which is what its dispatch URL expects.
  + kurly.headlessService(port=port)
  // The node's container logs. /var/log holds the symlinks the kubelet writes and
  // /var/lib/docker/containers the files some runtimes put them in; both
  // read-only.
  + kurly.hostPath('/var/log', type='Directory')
  + kurly.scratch('/tmp', '64Mi')
  // Reading another container's log files off the node needs a uid that may.
  + kurly.rootUser()
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
