// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// gravity — DNS, DHCP and TFTP for a local network, replicated across nodes and
// backed by an embedded etcd, with a web interface for the zones, records and
// leases. A composable kurly.stateful workload, because each member is an etcd
// peer with an identity and a volume that follows it. Import it and render with
// kurly.list:
//
//   local gravity = import 'github.com/metio/kurly/workloads/gravity/server.libsonnet';
//   kurly.list(gravity())
//
// IT RUNS ON THE NODE'S NETWORK, AND IT HAS TO. DHCP is answered from broadcast
// traffic that never reaches a pod behind a Service, so upstream's own compose
// file runs with host networking and so does this. Two consequences worth knowing
// before deploying it: the ports it opens ARE the node's ports, so two members
// cannot share a node — compose an anti-affinity rule — and nothing about it is
// isolated by a Service, so what reaches it is whatever reaches the node.
//
// SERVING :53 AND :67 IS THE PRIVILEGE. Both are below 1024, which the dropped-ALL
// default forbids binding; NET_BIND_SERVICE is granted by name, and the rest of
// the hardened posture stands — no root, read-only root filesystem, its own user
// namespace where the host namespaces allow one.
//
// DNS IS USEFUL ALONE; DHCP IS NOT. A single member answering DNS is a working
// deployment. DHCP wants to be the only server on its segment, which is a fact
// about the network rather than about this workload — and TFTP exists to net-boot
// the machines DHCP points at.
//
// Single writer per member: each carries its own etcd data on a ReadWriteOnce
// volume. Raising replicas adds etcd peers, which wants an odd number.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='gravity',
  image=defaultImage,
  // etcd peers. Odd numbers; one is a single-node deployment.
  replicas=1,
  storageSize='10Gi',
  storageClass=null,
  // Answer DHCP as well as DNS. Off by default: a DHCP server wants to be the
  // only one on its segment, and turning one on by accident breaks a network
  // rather than this workload.
  dhcp=false,
  // Serve TFTP, for net-booting the machines DHCP points at.
  tftp=false,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.stateful(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8008)
  + kurly.servicePort(8008)
  + kurly.extraPort('dns-tcp', 53)
  + kurly.extraPort('dns-udp', 53, protocol='UDP')
  + (if dhcp then kurly.extraPort('dhcp', 67, protocol='UDP') else {})
  + (if tftp then kurly.extraPort('tftp', 69, protocol='UDP') else {})
  + kurly.env({ DEBUG: 'false' } + env)
  // See the header: DHCP is broadcast traffic that never reaches a pod behind a
  // Service. kurly drops the pod's own user namespace with this, because the
  // kubelet refuses the combination.
  + kurly.hostNetwork()
  // The two privileged ports, granted by name rather than by running as root.
  + kurly.addCapabilities(['NET_BIND_SERVICE'])
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '128Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
