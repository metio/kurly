// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// dgraph/zero — the coordinator of a Dgraph cluster: it hands out the ranges of
// data each alpha group owns, moves them when the cluster changes shape, and
// keeps the membership. A composable kurly.stateful workload, because it is a
// Raft member with an identity and a volume that follows it. Import it and render
// alongside the alphas:
//
//   local zero = import 'github.com/metio/kurly/workloads/dgraph/zero.libsonnet';
//   local alpha = import 'github.com/metio/kurly/workloads/dgraph/alpha.libsonnet';
//   kurly.list([zero(), alpha()])
//
// THE ALPHAS ARE USELESS WITHOUT IT AND IT IS USELESS ALONE. Zero holds no graph
// data; it decides who holds what. Deploy both, and deploy zero first — an alpha
// that cannot reach it waits rather than serving.
//
// ONE ZERO IS NOT HIGH AVAILABILITY. Raft needs an odd number to tolerate a loss,
// so a cluster that must survive one failure wants three replicas and the peers
// pointing at each other through the headless Service this renders. One is the
// default because it is what a single-node deployment needs and because three
// costs three volumes.
//
// Serves the gRPC port on :5080 and its HTTP admin endpoint on :6080. Neither
// belongs on the internet: :6080 will move data and drop nodes for anyone who
// asks.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './zero.image', '\n');

function(
  name='dgraph-zero',
  image=defaultImage,
  // Raft wants an odd number. One is a single-node deployment, three tolerates
  // losing one.
  replicas=1,
  // How many alphas form each data group — the replication factor of the graph
  // itself, which is a different number from this stage's own replica count.
  shardReplicas=1,
  storageSize='10Gi',
  storageClass=null,
  extraArgs=[],
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.stateful(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(5080)
  + kurly.servicePort(5080)
  + kurly.extraPort('http', 6080)
  // A stable DNS name per pod is what lets the peers find each other; a Raft
  // member that changes address on every restart cannot rejoin its own cluster.
  + kurly.headlessService(port=5080, publishNotReady=true)
  + kurly.env(env)
  + kurly.command(['dgraph'])
  + kurly.args([
    'zero',
    '--my=$(POD_NAME).' + name + '-headless:5080',
    '--replicas=' + shardReplicas,
    '--wal=/dgraph/zw',
  ] + extraArgs)
  // The image runs as root and owns nothing that needs it; fsGroup makes the
  // write-ahead log writable.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/dgraph', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '256Mi')
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
