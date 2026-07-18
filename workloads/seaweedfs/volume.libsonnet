// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// seaweedfs (volume) — the data tier of a SPLIT SeaweedFS: `weed volume`, which
// stores the actual file content and reports itself to the master. A
// kurly.stateful workload; scale it by replicas for capacity, each server a pod
// with its own PVC. Point it at the master with masterEndpoint:
//
//   local volume = import 'github.com/metio/kurly/workloads/seaweedfs/volume.libsonnet';
//   kurly.list(volume(replicas=3, storageSize='100Gi',
//                     masterEndpoint='seaweedfs-master-0.seaweedfs-master-headless:9333'))
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// The workload version, stamped as app.kubernetes.io/version; the release
// pipeline overwrites version.txt with the calver.
local version = std.rstripChars(importstr './version.txt', '\n');

// A volume server MUST advertise a routable address, or the master hands clients
// an unreachable one and every read fails — its short hostname does not resolve
// cluster-wide, so advertise the pod's own IP through the downward API.
local advertisePodIP = {
  statefulset+: { spec+: { template+: { spec+: {
    containers: [
      c { env+: [{ name: 'POD_IP', valueFrom: { fieldRef: { fieldPath: 'status.podIP' } } }] }
      for c in super.containers
    ],
  } } } },
};

function(
  name='seaweedfs-volume',
  image='docker.io/chrislusf/seaweedfs:4.39',
  replicas=2,
  storageSize='10Gi',
  storageClass=null,
  masterEndpoint='seaweedfs-master-0.seaweedfs-master-headless:9333',
  maxVolumes=100,
)
  kurly.stateful(name, image)
  + kurly.version(version)
  // The image declares no non-root USER, so runAsNonRoot has no uid to admit
  // against; pin one, and its fsGroup makes the data volume writable.
  + kurly.runAs(1000)
  + kurly.port(8080)
  + kurly.replicas(replicas)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '64Mi')
  + advertisePodIP
  // -max bounds how many volume files this server will hold; the store sizes the
  // disk behind them. -ip is the address the server registers with the master.
  + kurly.args(['volume', '-mserver=' + masterEndpoint, '-dir=/data', '-ip=$(POD_IP)', '-ip.bind=0.0.0.0', '-max=' + maxVolumes])
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests={ cpu: '100m', memory: '256Mi' },
    limits={ memory: '512Mi' },
  )
  + {
    // The stateful kind's headless Service advertises port 80; make it the
    // volume port so peers reach it at <pod>.<name>-headless:8080.
    service+: {
      spec+: { ports: [{ name: 'volume', port: 8080, targetPort: 'http', protocol: 'TCP' }] },
    },
  }
