// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// seaweedfs (master) — the coordinator of a SPLIT SeaweedFS: `weed master`,
// which holds the cluster topology, assigns file IDs, and tells clients which
// volume server holds what. A kurly.stateful workload (a StatefulSet with a
// small PVC for its metadata and a headless Service for a stable address).
//
// This is one of three composable stages — master, volume, filer — that a
// consumer deploys together for a distributed store, as opposed to the all-in-one
// `server` stage. Deploy the master, then point the volume and filer stages at it:
//
//   local master = import 'github.com/metio/kurly/workloads/seaweedfs/master.libsonnet';
//   local volume = import 'github.com/metio/kurly/workloads/seaweedfs/volume.libsonnet';
//   kurly.list(master())
//   kurly.list(volume(masterEndpoint='seaweedfs-master-0.seaweedfs-master-headless:9333'))
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// The workload version, stamped as app.kubernetes.io/version; the release
// pipeline overwrites version.txt with the calver.
local version = std.rstripChars(importstr './version.txt', '\n');

// SeaweedFS peers reach one another by address, and a pod's short hostname is not
// resolvable cluster-wide — so advertise the pod's own routable IP, injected
// through the downward API. (A manifest patch, not a config knob: kurly has no
// downward-API env feature, and the merge survives later composition because it
// adds to the container rather than replacing it.)
local advertisePodIP = {
  statefulset+: { spec+: { template+: { spec+: {
    containers: [
      c { env+: [{ name: 'POD_IP', valueFrom: { fieldRef: { fieldPath: 'status.podIP' } } }] }
      for c in super.containers
    ],
  } } } },
};

function(
  name='seaweedfs-master',
  image='docker.io/chrislusf/seaweedfs:4.39',
  storageSize='1Gi',
  storageClass=null,
  defaultReplication='000',
)
  kurly.stateful(name, image)
  + kurly.version(version)
  // The image declares no non-root USER, so runAsNonRoot has no uid to admit
  // against; pin one, and its fsGroup makes the metadata volume writable.
  + kurly.runAs(1000)
  + kurly.port(9333)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '64Mi')
  + advertisePodIP
  // defaultReplication is a cluster-wide policy the master owns: '000' keeps one
  // copy of each volume (no redundancy), which suits a small cluster; '001' and
  // up need at least that many volume servers on distinct racks/nodes.
  + kurly.args(['master', '-mdir=/data', '-ip=$(POD_IP)', '-ip.bind=0.0.0.0', '-defaultReplication=' + defaultReplication])
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests={ cpu: '100m', memory: '128Mi' },
    limits={ memory: '256Mi' },
  )
  + {
    // The stateful kind's headless Service advertises port 80; make it the
    // master port so peers reach it at <pod>.<name>-headless:9333.
    service+: {
      spec+: { ports: [{ name: 'master', port: 9333, targetPort: 'http', protocol: 'TCP' }] },
    },
  }
