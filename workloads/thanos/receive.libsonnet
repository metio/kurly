// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// thanos receive — the Receiver: it accepts Prometheus remote-write, holds the
// recent data in a local TSDB, serves it to the Querier over the StoreAPI, and
// uploads completed blocks to object storage. It is the PUSH-based alternative to
// the scrape-and-sidecar path: point Prometheus `remote_write` at it instead of
// running a Thanos sidecar. Receivers form a hashring — incoming series are
// distributed across the pods by hash and replicated — so this is a stateful,
// identity-bearing workload (a kurly.stateful StatefulSet with a per-pod TSDB PVC
// and a headless Service). Import it, point it at object storage, and render with
// kurly.list:
//
//   local receive = import 'github.com/metio/kurly/workloads/thanos/receive.libsonnet';
//   kurly.list(receive(replicas=3, replicationFactor=2, objstoreSecret='thanos-objstore'))
//
// Prometheus writes to the remote-write port (:19291); the Querier reads it as a
// StoreAPI endpoint:
//   query(endpoints=['dnssrv+_grpc._tcp.thanos-receive-headless.monitoring.svc.cluster.local'])
//
// Each replica tags its data with a receive_replica external label so the Querier
// can deduplicate the replicated copies — set query(queryReplicaLabels including
// 'receive_replica'). This runs the combined router+ingestor mode; split routers
// are an --receive.* extraArgs concern. OBJECT STORAGE: the same objstore Secret
// the store reads (key `objstore.yaml`), which you create — kurly never mints it.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// The workload version, stamped as app.kubernetes.io/version; the release
// pipeline overwrites version.txt with the calver.
local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='thanos-receive',
  image='quay.io/thanos/thanos:v0.42.2',
  replicas=1,
  // How many receivers each series is written to. Must be <= replicas and is
  // usually odd (the receiver quorum-writes). 1 disables replication.
  replicationFactor=1,
  // The Secret naming the Thanos objstore config (key `objstore.yaml`), mounted
  // read-only; --objstore.config-file points at it.
  objstoreSecret='thanos-objstore',
  // How long the local TSDB keeps data before it lives only in object storage.
  tsdbRetention='15d',
  storageSize='10Gi',
  storageClass=null,
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
  // Extra `thanos receive` flags passed verbatim (--receive.tenant-header,
  // --tsdb.max-exemplars, split router/ingestor endpoints, …).
  extraArgs=[],
)
  // The hashring the receivers route across: every pod of this StatefulSet by its
  // stable DNS name on the gRPC port. A pod that is not up yet is retried, so the
  // full ring is safe to declare ahead of the rollout.
  local hashring = std.manifestJsonEx(
    [{
      hashring: 'default',
      endpoints: [
        { address: '%s-%d.%s-headless:10901' % [name, i, name] }
        for i in std.range(0, replicas - 1)
      ],
    }],
    '  ',
  );

  // Per-pod identity plus the two extra ports (metrics, remote-write) beyond the
  // gRPC StoreAPI that kurly.port names 'http'. POD_NAME lets each receiver name
  // itself in the hashring and label its own data.
  local podPatches = {
    statefulset+: { spec+: { template+: { spec+: {
      containers: [
        container {
          ports+: [
            { containerPort: 10902, name: 'metrics', protocol: 'TCP' },
            { containerPort: 19291, name: 'remote-write', protocol: 'TCP' },
          ],
          env+: [{ name: 'POD_NAME', valueFrom: { fieldRef: { fieldPath: 'metadata.name' } } }],
        }
        for container in super.containers
      ],
    } } } },
    service+: { spec+: { ports: [
      { name: 'grpc', port: 10901, targetPort: 'http', protocol: 'TCP' },
      { name: 'metrics', port: 10902, targetPort: 'metrics', protocol: 'TCP' },
      { name: 'remote-write', port: 19291, targetPort: 'remote-write', protocol: 'TCP' },
    ] } },
  };

  local args =
    [
      'receive',
      '--grpc-address=0.0.0.0:10901',
      '--http-address=0.0.0.0:10902',
      '--remote-write.address=0.0.0.0:19291',
      '--objstore.config-file=/etc/objstore/objstore.yaml',
      '--tsdb.path=/var/thanos/receive',
      '--tsdb.retention=' + tsdbRetention,
      // The external label that distinguishes each replica's copy, so the Querier
      // can deduplicate the replicated writes. $(POD_NAME) is the downward-API env.
      '--label=receive_replica="$(POD_NAME)"',
      '--receive.replication-factor=' + replicationFactor,
      // How this pod names itself in the hashring — must equal its hashring entry.
      '--receive.local-endpoint=$(POD_NAME).' + name + '-headless:10901',
      '--receive.hashrings-file=/etc/hashring/hashring.json',
    ]
    + extraArgs;

  kurly.stateful(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(10901)
  + kurly.args(args)
  // The thanos image ships no non-root user, and the restricted default demands
  // one; its fsGroup makes the TSDB volume writable.
  + kurly.runAs(1001)
  + kurly.store('/var/thanos/receive', storageSize, storageClass=storageClass)
  // The objstore config the consumer provides, and the generated hashring, on
  // separate paths so neither mount hides the other. Mounting an existing Secret
  // is kurly's key-material rule (it never authors one).
  + kurly.secretMount(objstoreSecret, '/etc/objstore')
  + kurly.config({ 'hashring.json': hashring }, mountPath='/etc/hashring')
  // TCP, not HTTP: the primary port is the gRPC StoreAPI.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + podPatches
