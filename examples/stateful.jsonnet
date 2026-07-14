// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// A stateful HTTP workload, exercising the storage-and-mounts features: an
// owned store (a PersistentVolumeClaim mounted for the app's data), a
// ConfigMap rendered from a filename->content map and mounted read-only, an
// EXISTING Secret mounted read-only (kurly never mints key material), and a
// writable scratch dir the read-only root filesystem needs for /tmp. A pinned
// non-root uid/gid with a matching fsGroup lets the pod own the store's files,
// and recreate avoids a rolling update deadlocking on the ReadWriteOnce volume.
local kurly = import '../main.libsonnet';

kurly.list(
  kurly.http('ledger', 'ghcr.io/example/ledger:1.4.0')
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.runAs(12345)
  + kurly.store('/var/lib/ledger', '10Gi', storageClass='fast-ssd')
  + kurly.config({ 'ledger.conf': 'mode = append-only\nfsync = always\n' }, mountPath='/etc/ledger')
  + kurly.secretMount('ledger-signing-key', '/etc/ledger-keys', optional=true, defaultMode=256)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.probes('/healthz')
)
