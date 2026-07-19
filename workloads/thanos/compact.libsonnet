// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// thanos compact — the Compactor: it compacts raw blocks in object storage into
// larger ones, builds the 5m and 1h downsampled resolutions, and applies
// retention — the background maintenance that keeps the bucket the store gateway
// reads fast and bounded. Like store it reads and writes the same object store,
// but it serves no StoreAPI: it is a `thanos compact --wait` process with a local
// scratch PVC for the blocks it downloads to compact. Import it, point it at the
// bucket, and render with kurly.list:
//
//   local compact = import 'github.com/metio/kurly/workloads/thanos/compact.libsonnet';
//   kurly.list(compact(objstoreSecret='thanos-objstore'))
//
// SINGLETON: exactly one compactor may run against a bucket. A second one runs
// concurrent compaction over the same blocks and corrupts the data, so this
// pins replicas to 1 and asserts it, and rolls with Recreate so a deploy never
// briefly overlaps two. Shard a large bucket with --selector.relabel-config
// across SEPARATE compactors, each owning a disjoint slice — never two over the
// same slice.
//
// OBJECT STORAGE: the same objstore Secret the store reads (key `objstore.yaml`),
// which you create — kurly never mints it (fill it with kurly.externalSecret).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// The workload version, stamped as app.kubernetes.io/version; the release
// pipeline overwrites version.txt with the calver.
local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='thanos-compact',
  image='quay.io/thanos/thanos:v0.42.2',
  // The Secret naming the Thanos objstore config (key `objstore.yaml`), mounted
  // read-only; --objstore.config-file points at it.
  objstoreSecret='thanos-objstore',
  // The scratch PVC the compactor downloads blocks into. Sizing follows the
  // largest blocks it compacts, not the whole bucket.
  storageSize='10Gi',
  storageClass=null,
  // Retention per resolution. `0d` keeps that resolution forever (the Thanos
  // default) — set a duration to expire old blocks and bound the bucket.
  retentionRaw='0d',
  retention5m='0d',
  retention1h='0d',
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
  // Extra `thanos compact` flags passed verbatim (--deduplication.replica-label,
  // --downsampling.disable, --selector.relabel-config for sharding, …).
  extraArgs=[],
)
  local args =
    [
      'compact',
      // Run continuously, compacting on an interval, rather than once and exiting.
      '--wait',
      '--http-address=0.0.0.0:10902',
      '--data-dir=/var/thanos/compact',
      '--objstore.config-file=/etc/thanos/objstore.yaml',
      '--retention.resolution-raw=' + retentionRaw,
      '--retention.resolution-5m=' + retention5m,
      '--retention.resolution-1h=' + retention1h,
    ]
    + extraArgs;

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  // Never overlap two compactors, not even for a rollout's handover moment.
  + kurly.recreate()
  + kurly.port(10902)
  + kurly.servicePort(10902)
  + kurly.args(args)
  // The thanos image ships no non-root user, and the restricted default demands
  // one; its fsGroup makes the scratch volume writable.
  + kurly.runAs(1001)
  + kurly.store('/var/thanos/compact', storageSize, storageClass=storageClass)
  // The objstore config the consumer provides; mounting an existing Secret is
  // kurly's key-material rule (it never authors one).
  + kurly.secretMount(objstoreSecret, '/etc/thanos')
  + kurly.readinessProbe({ httpGet: { path: '/-/ready', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/-/healthy', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + {
    // Asserted against the MERGED config, since the replica count can arrive by
    // composition (compact() + kurly.replicas(2)) rather than as a parameter.
    assert self.config.replicas == 1 :
           'thanos compact: replicas must be 1 — a second compactor against the same bucket runs concurrent compaction and corrupts the data. Shard with separate compactors over disjoint slices instead. Got '
           + std.toString(self.config.replicas) + '.',
  }
