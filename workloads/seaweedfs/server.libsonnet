// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// seaweedfs (server) — SeaweedFS as an all-in-one object store: the kurly.stateful
// shape, a StatefulSet with a per-pod PVC and a headless Service, running
// `weed server -s3` so one process is master + volume + filer + an S3 gateway.
// It gives a cluster an S3 API (port 8333) backed by a PersistentVolume — an
// in-cluster target for the things that expect S3, such as a cnpg-cluster's WAL
// and base backups. Import it, size the volume, and render with kurly.list:
//
//   local seaweedfs = import 'github.com/metio/kurly/workloads/seaweedfs/server.libsonnet';
//   kurly.list(seaweedfs(storageSize='50Gi', storageClass='fast'))
//
// This is the single-node all-in-one — the SeaweedFS quick-start shape, and the
// right one for a modest in-cluster S3. Scaling the roles apart (dedicated
// master/volume/filer tiers) is a different topology, not more replicas of this,
// so it would be its own stage rather than a replica count here.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// The workload version, stamped as app.kubernetes.io/version; the release
// pipeline overwrites version.txt with the calver.
local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='seaweedfs',
  image='docker.io/chrislusf/seaweedfs:4.39',
  storageSize='10Gi',
  storageClass=null,
)
  kurly.stateful(name, image)
  + kurly.version(version)
  // The image declares no non-root USER, so runAsNonRoot has no uid to admit
  // against; pin one, and its fsGroup makes the data volume writable to it.
  + kurly.runAs(1000)
  // The S3 gateway is the client-facing endpoint; the master (9333), volume
  // (8080), and filer (8888) ports serve the cluster itself and are reached on
  // the pod when needed.
  + kurly.port(8333)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  // Everything durable lives under -dir on the PVC; /tmp is a small scratch for
  // the S3 gateway's staging, so the root filesystem stays read-only.
  + kurly.scratch('/tmp', '256Mi')
  + kurly.args(['server', '-dir=/data', '-s3'])
  // The S3 gateway speaks HTTP, but readiness here is just the port accepting a
  // connection — a GET / is an S3 API call, not a health endpoint.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests={ cpu: '100m', memory: '256Mi' },
    limits={ memory: '512Mi' },
  )
  + {
    // The stateful kind's headless Service advertises port 80; make it the S3
    // port so a client reaches the gateway at <pod>.<name>-headless:8333, the
    // endpoint the README and any S3 config point at.
    service+: {
      spec+: { ports: [{ name: 's3', port: 8333, targetPort: 'http', protocol: 'TCP' }] },
    },
  }
