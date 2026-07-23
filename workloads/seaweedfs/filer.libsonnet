// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// seaweedfs (filer) — the access tier of a SPLIT SeaweedFS: `weed filer`, which
// puts a filesystem and (with s3=true) an S3 gateway over the volume servers,
// keeping its own metadata. A kurly.stateful workload. Point it at the master;
// clients reach the S3 API at <pod>.<name>-headless:8333:
//
//   local filer = import 'github.com/metio/kurly/workloads/seaweedfs/filer.libsonnet';
//   kurly.list(filer(masterEndpoint='seaweedfs-master-0.seaweedfs-master-headless:9333'))
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// The workload version, stamped as app.kubernetes.io/version; the release
// pipeline overwrites version.txt with the calver.
local version = std.rstripChars(importstr './version.txt', '\n');

// The filer registers with the master and is reached by clients, so it must
// advertise a routable address — its short hostname is not resolvable
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
  name='seaweedfs-filer',
  image='docker.io/chrislusf/seaweedfs:4.40',
  storageSize='1Gi',
  storageClass=null,
  masterEndpoint='seaweedfs-master-0.seaweedfs-master-headless:9333',
  s3=true,
)
  // With the S3 gateway the client-facing port is 8333; without it, the filer's
  // own HTTP is 8888. The port name stays kurly's `http` either way.
  local primaryPort = if s3 then 8333 else 8888;
  local portName = if s3 then 's3' else 'filer';

  kurly.stateful(name, image)
  + kurly.version(version)
  // The image declares no non-root USER, so runAsNonRoot has no uid to admit
  // against; pin one, and its fsGroup makes the metadata volume writable.
  + kurly.runAs(1000)
  + kurly.port(primaryPort)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '64Mi')
  + advertisePodIP
  + kurly.args(
    ['filer', '-master=' + masterEndpoint, '-ip=$(POD_IP)', '-ip.bind=0.0.0.0']
    + (if s3 then ['-s3', '-s3.port=8333'] else [])
  )
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests={ cpu: '100m', memory: '256Mi' },
    limits={ memory: '512Mi' },
  )
  + {
    // The stateful kind's headless Service advertises port 80; make it the
    // client-facing port so consumers reach it at <pod>.<name>-headless:<port>.
    service+: {
      spec+: { ports: [{ name: portName, port: primaryPort, targetPort: 'http', protocol: 'TCP' }] },
    },
  }
