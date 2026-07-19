// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// thanos store — the Store Gateway: it serves historical metric blocks from
// object storage over the StoreAPI (gRPC), so the Querier can reach data older
// than what the Prometheus sidecars still hold locally. Like query it is a plain
// `thanos store` workload (not an operator custom resource), but stateful: it
// keeps a local cache of block index headers and chunks, so it is a kurly.stateful
// StatefulSet with a per-pod PVC and a headless Service (whose SRV records the
// Querier discovers with `dnssrv+`). Import it, point it at your object store, and
// render with kurly.list:
//
//   local store = import 'github.com/metio/kurly/workloads/thanos/store.libsonnet';
//   kurly.list(store(objstoreSecret='thanos-objstore'))
//
// Then add it to the Querier's endpoints:
//   query(endpoints=['dnssrv+_grpc._tcp.thanos-store-headless.monitoring.svc.cluster.local'])
//
// OBJECT STORAGE: the store reads its bucket from a Thanos objstore config (a
// YAML naming the bucket, endpoint, and credentials). kurly never mints the
// Secret holding it — create one with an `objstore.yaml` key (fill it from your
// secrets store with kurly.externalSecret) and name it in objstoreSecret. It
// pairs with the seaweedfs workload: point the config at its S3 gateway.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// The workload version, stamped as app.kubernetes.io/version; the release
// pipeline overwrites version.txt with the calver.
local version = std.rstripChars(importstr './version.txt', '\n');

// The store serves the StoreAPI on gRPC :10901 (what the Querier connects to) and
// metrics/health on HTTP :10902. kurly.port names the primary container port
// 'http'; add the metrics port and publish both on the headless Service, the
// gRPC one under an `_grpc._tcp` SRV name the Querier's dnssrv+ resolves.
local dualPorts = {
  statefulset+: { spec+: { template+: { spec+: {
    containers: [
      container { ports+: [{ containerPort: 10902, name: 'metrics', protocol: 'TCP' }] }
      for container in super.containers
    ],
  } } } },
  service+: { spec+: { ports: [
    { name: 'grpc', port: 10901, targetPort: 'http', protocol: 'TCP' },
    { name: 'metrics', port: 10902, targetPort: 'metrics', protocol: 'TCP' },
  ] } },
};

function(
  name='thanos-store',
  image='quay.io/thanos/thanos:v0.42.2',
  replicas=1,
  // The Secret naming the Thanos objstore config (key `objstore.yaml`), which you
  // create — kurly never mints it. Mounted read-only; --objstore.config-file
  // points at it.
  objstoreSecret='thanos-objstore',
  // The local block-cache PVC. The cache is rebuildable, but a PVC spares the
  // store re-downloading every index header on restart.
  storageSize='10Gi',
  storageClass=null,
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
  // Extra `thanos store` flags passed verbatim (--index-cache-size,
  // --chunk-pool-size, --selector.relabel-config for sharding, …).
  extraArgs=[],
)
  local args =
    [
      'store',
      '--grpc-address=0.0.0.0:10901',
      '--http-address=0.0.0.0:10902',
      '--data-dir=/var/thanos/store',
      '--objstore.config-file=/etc/thanos/objstore.yaml',
    ]
    + extraArgs;

  kurly.stateful(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(10901)
  + kurly.args(args)
  // The thanos image ships no non-root user, and the restricted default demands
  // one; its fsGroup makes the cache volume writable.
  + kurly.runAs(1001)
  + kurly.store('/var/thanos/store', storageSize, storageClass=storageClass)
  // The objstore config the consumer provides; mounting an existing Secret is
  // kurly's key-material rule (it never authors one).
  + kurly.secretMount(objstoreSecret, '/etc/thanos')
  // TCP, not HTTP: the primary port is the gRPC StoreAPI, and readiness that the
  // blocks are synced is the operator's concern, not a rollout gate.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + dualPorts
