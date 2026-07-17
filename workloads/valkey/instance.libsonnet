// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// valkey (single instance) — a persistent Valkey server on the official upstream
// image, as a kurly.stateful workload: a StatefulSet with a per-pod PVC (through
// the store feature's volumeClaimTemplate) and the headless Service that names
// it. This is the single-instance stage; a primary+replica stage and a
// cluster-mode stage slot in beside it later without touching this one.
//
//   local valkey = import 'github.com/metio/kurly/workloads/valkey/instance.libsonnet';
//   kurly.list(valkey(storageSize='5Gi'))
//
// Clients reach it at <pod>.<name>-headless.<namespace>.svc on port 6379.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// Valkey is the BSD-licensed fork of Redis and takes the same configuration, so
// `image` also accepts a Redis build (they share the uid, the flags and /data).
// Name the workload for its role when you do — a Redis server answering to a
// Service called `valkey-headless` is a thing nobody wants to debug at 3am. The
// official image is used verbatim — kurly does not ship a customized build.
//
// Naming it for its role is also what lets a consumer stop caring which store it
// got: the protocol is shared with dragonfly, so
//
//   kurly.list(valkey(name='cache'))
//   worker + kurly.env({ REDIS_URL: 'redis://cache-headless:6379' })
//
// swaps between engines by editing one manifest.
function(
  name='valkey',
  image='docker.io/valkey/valkey:9.1.0',
  storageSize='1Gi',
  storageClass=null,
  maxMemory=null,
)
  kurly.stateful(name, image)
  // The container runs as the image's non-root valkey user (uid 999); fsGroup
  // matches so the pod owns its PVC.
  + kurly.runAs(999)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  // Append-only persistence, writing into the mounted volume. maxmemory caps the
  // dataset and evicts least-recently-used keys once full (a cache posture); left
  // unset, Valkey grows until the pod's memory limit.
  + kurly.args(
    ['--appendonly', 'yes', '--dir', '/data']
    + (if maxMemory == null then [] else ['--maxmemory', maxMemory, '--maxmemory-policy', 'allkeys-lru'])
  )
