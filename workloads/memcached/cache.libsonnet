// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// memcached — an in-memory cache sharded by the CLIENT, as a StatefulSet whose
// storage is nothing and whose identity is everything.
//
// memcached has no replication and no persistence, so unlike the valkey cache
// it cannot hand its dataset to a new version: every upgrade starts cold. What
// it can do is bound the loss. Clients pick a server by consistent-hashing the
// key over the server list, so as long as the names in that list are stable, a
// restart costs a client the 1/N of its keyspace that lives on the pod being
// restarted — and nothing else.
//
// That is the whole reason this is a StatefulSet rather than a Deployment. The
// StatefulSet is here for stable names (memcached-0, memcached-1, …) and their
// DNS records, NOT for storage — there is no volume anywhere in this workload.
// Authored as a Deployment the manifests would look much the same and behave
// completely differently: every pod would get a fresh random name on every roll,
// every name in the client's hash ring would change at once, and the entire
// cache would be invalidated rather than 1/N of it. A StatefulSet also replaces
// one pod at a time, so the other N-1 shards keep serving throughout.
//
// Clients address the pods directly by their stable DNS names:
//
//   <name>-0.<name>-headless:11211
//   <name>-1.<name>-headless:11211
//
// Scaling changes the server list and therefore reshuffles the ring, so treat
// `replicas` as part of the client's configuration, not a free-running knob.
//
//   local memcached = import 'github.com/metio/kurly/workloads/memcached/cache.libsonnet';
//   kurly.list(memcached(replicas=3, memoryMB=256))
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// The workload version, stamped as app.kubernetes.io/version; the release
// pipeline rewrites 'dev' to the calver.
local version = 'dev';

local port = 11211;

function(
  name='memcached',
  image='docker.io/library/memcached:1.6.45',
  replicas=3,
  memoryMB=64,
  maxConnections=1024,
)
  // The client's hash ring is built from the server list, so a single replica is
  // a legitimate (if pointless) cache while zero is a broken one.
  assert replicas >= 1 : 'memcached: replicas must be at least 1';
  assert memoryMB > 0 : 'memcached: memoryMB must be greater than 0';

  // `-m` caps the ITEM cache only: slab metadata, per-connection buffers and the
  // binary itself all live outside it, so a container limit equal to -m is an
  // OOMKill waiting for a busy day. The limit is derived from the same number
  // that produces -m, so the two cannot drift apart — the usual failure being a
  // -m raised without the limit following it.
  local memoryLimitMB = std.ceil(memoryMB * 1.25) + 32;

  kurly.stateful(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  // The image declares `USER memcache` — a name, not a number — and the
  // restricted default asks the kubelet to prove the user is not root, which it
  // cannot do from a name. Without a numeric uid every pod fails admission with
  // CreateContainerConfigError before memcached ever runs. 11211 is the uid the
  // image gives that account (it numbers the user to match the port).
  + kurly.runAs(11211)
  + kurly.port(port)
  + kurly.args(['-m', std.toString(memoryMB), '-c', std.toString(maxConnections)])
  + kurly.resources(
    requests={ cpu: '50m', memory: '%dMi' % memoryLimitMB },
    limits={ memory: '%dMi' % memoryLimitMB },
  )
  // memcached speaks its own text protocol, not HTTP, so readiness is the port
  // accepting a connection. The image ships no shell utilities to speak the
  // protocol with, and a probe is not worth an extra container.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + {
    // -m and the memory limit are two views of one number, and only one of them
    // is enforced by the kernel. kurly.resources() REPLACES the limits object
    // rather than merging into it, so composing it for an unrelated reason —
    // a CPU request, an ephemeral-storage limit — drops the derived memory
    // limit entirely and leaves memcached told to cache memoryMB MB with no bound
    // at all. Overriding it directly is no better: the flag still names the old
    // number and the pod is OOMKilled at exactly the moment the cache fills,
    // which looks like a memcached bug rather than a manifest one.
    //
    // Asserted against the MERGED config, since the override arrives by
    // composition. To size the cache, move memoryMB: both follow it.
    local wanted = '%dMi' % memoryLimitMB,
    assert std.objectHas(self.config.resources, 'limits')
           && std.objectHas(self.config.resources.limits, 'memory')
           && self.config.resources.limits.memory == wanted :
           'memcached: the memory limit is derived from memoryMB (-m %d needs %s) and must not be set by hand — '
           % [memoryMB, wanted]
           + 'kurly.resources() replaces the whole limits object, so it drops or contradicts the derived limit and the pod is OOMKilled when the cache fills. '
           + 'Set memoryMB instead; it moves -m and the limit together. Got: '
           + std.toString(if std.objectHas(self.config.resources, 'limits') then self.config.resources.limits else {}) + '.',
  }
  + {
    // The stateful kind gives its headless Service the http port (80). Nothing
    // routes through a headless Service — DNS answers with pod IPs and the
    // client dials the pod itself — but a memcached manifest advertising port 80
    // reads as a mistake, so name it for what it is.
    service+: {
      spec+: {
        ports: [{ name: 'memcache', port: port, targetPort: 'http', protocol: 'TCP' }],
      },
    },
  }
