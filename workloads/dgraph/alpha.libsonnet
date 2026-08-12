// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// dgraph/alpha — the half of a Dgraph cluster that holds the graph and answers
// queries, over GraphQL and DQL. A composable kurly.stateful workload: each alpha
// owns a shard of the data on its own volume, so it needs a stable identity.
// Import it and render alongside a zero:
//
//   local zero = import 'github.com/metio/kurly/workloads/dgraph/zero.libsonnet';
//   local alpha = import 'github.com/metio/kurly/workloads/dgraph/alpha.libsonnet';
//   kurly.list([zero(), alpha(replicas=3)])
//
// Serves the HTTP and GraphQL endpoints on :8080 and gRPC on :9080 — compose an
// exposure onto :8080 if clients are outside the cluster.
//
// IT WILL NOT START WITHOUT A ZERO, and that is by design rather than a bug to
// work around: the alphas ask zero which part of the graph they own. `zeroHost`
// points at the zero stage's headless Service.
//
// SECURITY IS OFF UNTIL YOU TURN IT ON. Dgraph's admin endpoints and its Ratel UI
// accept whoever reaches them; `whitelist` is the CIDR list allowed to call the
// admin API, and it defaults to nothing rather than to the private ranges,
// because a default that admits a whole cluster network is not one anybody chose.
// The ACL and encryption features are Enterprise; the open-source build has the
// whitelist and whatever sits in front.
//
// REPLICAS ARE SHARDS, NOT COPIES. Raising this number adds capacity; how many
// copies exist of each piece of data is zero's `shardReplicas`. Setting one
// without the other is how a Dgraph deployment ends up with no redundancy while
// looking three times bigger.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './alpha.image', '\n');

function(
  name='dgraph-alpha',
  image=defaultImage,
  replicas=1,
  // The zero stage's headless Service.
  zeroHost='dgraph-zero-headless',
  zeroPort=5080,
  // CIDRs allowed to call the admin API. Empty admits nobody.
  whitelist=[],
  storageSize='50Gi',
  storageClass=null,
  extraArgs=[],
  env={},
  resources={ requests: { cpu: '500m', memory: '2Gi' }, limits: { memory: '8Gi' } },
  labels={},
  annotations={},
)
  kurly.stateful(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.extraPort('grpc', 9080)
  + kurly.headlessService(port=8080, publishNotReady=true)
  + kurly.env(env)
  // --my= advertises the address peers reach this member at, and it has to be
  // THIS pod's stable name. Kubernetes only expands $(POD_NAME) in args when the
  // container declares it, and leaves an undeclared one as the literal text —
  // which starts fine and tells every peer to connect to a host that does not
  // exist.
  + kurly.envField('POD_NAME', 'metadata.name')
  + kurly.command(['dgraph'])
  + kurly.args([
    'alpha',
    '--my=$(POD_NAME).' + name + '-headless:7080',
    '--zero=' + zeroHost + ':' + zeroPort,
    '--postings=/dgraph/p',
    '--wal=/dgraph/w',
  ] + (if whitelist != [] then ['--security=whitelist=' + std.join(',', whitelist)] else []) + extraArgs)
  // The image runs as root and owns nothing that needs it; fsGroup makes the
  // posting list and write-ahead log writable.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/dgraph', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '1Gi')
  // A cold alpha replays its write-ahead log before it answers, which on a large
  // graph takes longer than a liveness probe should wait.
  + kurly.startupProbe({ httpGet: { path: '/health', port: 'http' }, periodSeconds: 10, failureThreshold: 60 })
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
