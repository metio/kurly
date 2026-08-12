// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// coroot/node-agent — the half of Coroot that actually measures: an eBPF agent on
// every node that traces TCP connections, container resource use, logs and
// profiles, and exports them as metrics. A composable kurly.daemon workload.
// Import it and render alongside the server:
//
//   local server = import 'github.com/metio/kurly/workloads/coroot/server.libsonnet';
//   local agent = import 'github.com/metio/kurly/workloads/coroot/node-agent.libsonnet';
//   kurly.list([server(), agent()])
//
// Serves its metrics on :80 — point Prometheus at it, or compose
// kurly.serviceMonitor() if the Prometheus Operator is doing the scraping.
//
// THIS ONE IS PRIVILEGED, AND THERE IS NO SMALLER VERSION. It attaches eBPF
// programs that trace every container's syscalls and network activity, shares the
// node's PID namespace so it can resolve a process to the container that owns it,
// and reads the cgroup hierarchy to attribute what it sees. Upstream's own
// manifest is privileged with hostPID, and this stage matches it rather than
// inventing a weaker set that would silently measure less. That makes it a
// cluster add-on, not a tenant workload — the catalogue reports it as
// clusterScoped and PSS-privileged so nobody deploys it by accident.
//
// A privileged agent on every node is a large trust decision, and the honest
// framing is that it is the same one every eBPF observability tool asks for. It
// belongs in a namespace only cluster operators can write to.
//
// KERNEL 5.1 OR NEWER. The eBPF programs will not load on anything older, and the
// agent exits rather than degrading.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './node-agent.image', '\n');

function(
  name='coroot-node-agent',
  image=defaultImage,
  port=80,
  // Where the agent ships what it collects. Left null it only exposes metrics for
  // a Prometheus to scrape.
  collectorEndpoint=null,
  extraArgs=[],
  resources={ requests: { cpu: '100m', memory: '200Mi' }, limits: { memory: '1Gi' } },
  env={},
  labels={},
  annotations={},
)
  kurly.daemon(name, image)
  + kurly.version(version)
  + kurly.port(port)
  + kurly.env(env)
  + kurly.command(['coroot-node-agent'])
  + kurly.args(
    ['--listen=0.0.0.0:' + port, '--cgroupfs-root=/host/sys/fs/cgroup']
    + (if collectorEndpoint != null then ['--collector-endpoint=' + collectorEndpoint] else [])
    + extraArgs
  )
  // See the header: upstream's own manifest is privileged with hostPID, and a
  // weaker set would measure less without saying so.
  + kurly.privileged()
  + kurly.rootUser()
  + kurly.hostPID()
  // The cgroup hierarchy it attributes usage from, and the tracing and debug
  // filesystems it attaches eBPF programs through.
  + kurly.hostPath('/host/sys/fs/cgroup', path='/sys/fs/cgroup', type='Directory')
  + kurly.hostPath('/sys/kernel/tracing', type='Directory', readOnly=false)
  + kurly.hostPath('/sys/kernel/debug', type='Directory', readOnly=false)
  + kurly.scratch('/tmp', '256Mi')
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
