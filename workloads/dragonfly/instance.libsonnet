// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// dragonfly — a RESP-speaking in-memory store, as a kurly.stateful workload with
// a per-pod PVC and a headless Service. Clients reach it at
// <pod>.dragonfly-headless.<namespace>.svc on port 6379.
//
// Dragonfly answers the same protocol as Valkey and Redis, so a client cannot
// tell them apart — but it is NOT a fork of either, and the differences are in
// exactly the places a workload has to get right:
//
//   - it rejects Redis's flags outright (`--appendonly` is an unknown flag, and
//     an unknown flag is fatal), persisting through snapshots instead;
//   - it runs one io thread per core it can SEE, which in a container is the
//     node's core count, not the pod's CPU limit;
//   - it refuses to start unless maxmemory is at least 256MiB per io thread.
//
// Those last two compound into the failure this recipe exists to prevent: left
// to itself on a 64-core node, Dragonfly starts 64 threads, demands 16GiB, and
// exits before serving anything — however small the pod's CPU limit is. So the
// thread count is always pinned, the CPU is sized from it (Dragonfly's model is
// a thread per core), and the memory floor is asserted at render rather than
// discovered as a CrashLoop.
//
//   local dragonfly = import 'github.com/metio/kurly/workloads/dragonfly/instance.libsonnet';
//   kurly.list(dragonfly(maxMemoryMB=2048, threads=4))
//
// Name it for its role rather than its engine and a consumer never learns which
// store it got — the protocol is the same:
//
//   kurly.list(dragonfly(name='cache'))
//   worker + kurly.env({ REDIS_URL: 'redis://cache-headless:6379' })
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// The workload version, stamped as app.kubernetes.io/version; the release
// pipeline rewrites 'dev' to the calver.
local version = 'dev';

// Dragonfly's own floor: it exits at startup rather than run under-provisioned.
local mibPerThread = 256;

function(
  name='dragonfly',
  image='ghcr.io/dragonflydb/dragonfly:v1.39.0',
  storageSize='1Gi',
  storageClass=null,
  maxMemoryMB=512,
  threads=2,
  snapshotCron=null,
)
  assert threads >= 1 : 'dragonfly: threads must be at least 1';
  // Dragonfly checks this itself and exits — "There are N threads, so X are
  // required. Exiting..." — so the pod would CrashLoop with the answer buried in
  // its log. Failing the render says it before anything is applied.
  assert maxMemoryMB >= mibPerThread * threads :
         'dragonfly: maxMemoryMB must be at least %d (%dMiB per io thread × %d threads), or Dragonfly refuses to start'
         % [mibPerThread * threads, mibPerThread, threads];

  // maxmemory caps the dataset; the process needs room beyond it for its own
  // allocator, connections and snapshotting. Deriving the limit from the same
  // number that produces --maxmemory keeps the two from drifting.
  local memoryLimitMB = std.ceil(maxMemoryMB * 1.25);

  kurly.stateful(name, image)
  // The image ships a `dfly` account at uid 999 but declares no USER, so the
  // restricted default's runAsNonRoot has no numeric uid to verify and the pod
  // would fail admission before starting.
  + kurly.runAs(999)
  + kurly.port(6379)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.args(
    [
      '--dir',
      '/data',
      '--maxmemory',
      '%dmb' % maxMemoryMB,
      // Never left to Dragonfly to decide: it would count the node's cores.
      '--proactor_threads',
      std.toString(threads),
    ]
    // Dragonfly writes a snapshot on shutdown; a cron keeps one from a crash
    // too. Left unset there is no periodic snapshot, which is the cache posture.
    + (if snapshotCron == null then [] else ['--snapshot_cron', snapshotCron])
  )
  + kurly.resources(
    // A thread per core is Dragonfly's model, so the CPU follows the thread
    // count rather than being tuned separately.
    requests={ cpu: '%d' % threads, memory: '%dMi' % memoryLimitMB },
    limits={ memory: '%dMi' % memoryLimitMB },
  )
  // Dragonfly speaks RESP, not HTTP, so readiness is the port accepting a
  // connection.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + {
    // The stateful kind gives its headless Service the http port (80); nothing
    // routes through a headless Service, but a RESP manifest advertising port 80
    // reads as a mistake.
    service+: {
      spec+: { ports: [{ name: 'resp', port: 6379, targetPort: 'http', protocol: 'TCP' }] },
    },
  }
