// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// cadvisor — per-container resource usage and performance metrics, read straight
// off the node's cgroups and exported for Prometheus. A composable kurly.daemon
// workload, because the thing it measures is the node. Import it and render with
// kurly.list:
//
//   local cadvisor = import 'github.com/metio/kurly/workloads/cadvisor/agent.libsonnet';
//   kurly.list(cadvisor() + kurly.serviceMonitor())
//
// Serves the UI and /metrics on :8080.
//
// THE KUBELET ALREADY EMBEDS IT. Every Kubernetes node exposes cAdvisor's metrics
// at /metrics/cadvisor on the kubelet, and a cluster scraping those needs nothing
// here. This stage is for the cases where that is not enough: a node whose
// kubelet metrics are turned off, a machine outside the cluster, or a deployment
// that wants cAdvisor's own UI and the per-container detail the kubelet's
// endpoint trims. Reach for the kubelet first.
//
// WHAT IT READS. The node's cgroup and container state: the root filesystem to
// find them, /sys for the cgroup hierarchy, /var/run for the runtime's state, and
// /dev/disk to name block devices in the I/O metrics. All read-only, and no
// capability beyond that is asked for — the paths are the privilege here.
//
// A CONTAINER RUNTIME'S DATA DIRECTORY is not mounted by default. cAdvisor reads
// image and layer sizes from it, and its path differs per runtime and per distro
// (/var/lib/docker, /var/lib/containerd, elsewhere on a k3s node), so
// `runtimeDataDir` names it rather than guessing wrong and reporting nothing.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './agent.image', '\n');

function(
  name='cadvisor',
  image=defaultImage,
  // The container runtime's data directory, for image and layer sizes. Its path
  // differs per runtime and distribution, so there is no default worth guessing.
  runtimeDataDir=null,
  // Appended to cAdvisor's own flags — --housekeeping_interval, --store_container_labels
  // and the rest.
  extraArgs=[],
  resources={ requests: { cpu: '150m', memory: '200Mi' }, limits: { memory: '2Gi' } },
  env={},
  labels={},
  annotations={},
)
  kurly.daemon(name, image)
  + kurly.version(version)
  + kurly.port(8080)
  + kurly.env(env)
  + kurly.args(['--housekeeping_interval=10s'] + extraArgs)
  // The node's own state, all read-only. cAdvisor runs as root because the paths
  // it reads are root-owned on every distribution.
  + kurly.rootUser()
  + kurly.hostPath('/rootfs', path='/', type='Directory')
  + kurly.hostPath('/var/run', type='Directory')
  + kurly.hostPath('/sys', type='Directory')
  + kurly.hostPath('/dev/disk', type='Directory')
  + (if runtimeDataDir != null then kurly.hostPath(runtimeDataDir, type='Directory') else {})
  + kurly.readinessProbe({ httpGet: { path: '/healthz', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/healthz', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
