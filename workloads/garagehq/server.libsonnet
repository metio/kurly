// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// garagehq — a Garage node: S3-compatible object storage that expects its copies
// to live in different buildings, so it is written for links that are slow and
// occasionally gone rather than for a rack. The kurly.stateful shape (a
// StatefulSet with a per-pod PVC and a headless Service), serving the S3 API on
// :3900 with the static-website server on :3902 and the admin API on :3903.
// Import it, size the volume, and render with kurly.list:
//
//   local garage = import 'github.com/metio/kurly/workloads/garagehq/server.libsonnet';
//   kurly.list(garage(storageSize='100Gi', storageClass='fast'))
//
// A FRESH NODE SERVES NOTHING. Garage stores no object until a cluster layout
// assigns capacity to the node, and that is an operator command against the
// running pod, not a manifest:
//
//   kubectl exec garage-0 -- /garage status                 # read the node id
//   kubectl exec garage-0 -- /garage layout assign -z dc1 -c 100G <id>
//   kubectl exec garage-0 -- /garage layout apply --version 1
//
// The pod is Ready before that happens — the port is open, the layout is empty —
// so a probe cannot stand in for it. Keys and buckets are the same kind of
// runtime state (`/garage key create`, `/garage bucket create`).
//
// The Secret is not optional: Garage refuses to start without an rpc_secret, so
// secretName must exist before the pod is scheduled. GARAGE_RPC_SECRET is the
// shared key nodes authenticate to one another with — every node of a cluster
// carries the SAME value, and changing it partitions the cluster.
//
// SCALING OUT IS NOT A REPLICA COUNT. Garage's whole subject is placing copies
// across sites, and a second replica here is a second node in the same
// namespace on the same layout, still with replicationFactor copies of every
// object. A real Garage cluster is one of these per site, each with its own
// zone in the layout — so raise replicas only after the layout has zones to
// spread over.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='garage',
  image=defaultImage,
  storageSize='20Gi',
  storageClass=null,
  replicationFactor=1,
  s3Region='garage',
  s3RootDomain='.s3.garage.localhost',
  webRootDomain='.web.garage.localhost',
  secretName='garage',
  config=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  // Garage reads one TOML file and nothing else; only the secrets come from the
  // environment. rpc_public_addr is deliberately ABSENT: unset, Garage takes the
  // address of its own interface, which in a pod is the routable pod IP. A stable
  // name would be the pod's headless record, and that is per-pod — one shared
  // ConfigMap cannot hold a different one for each replica.
  local defaultConfig = |||
    metadata_dir = "/var/lib/garage/meta"
    data_dir = "/var/lib/garage/data"
    db_engine = "lmdb"

    replication_factor = %d

    rpc_bind_addr = "[::]:3901"

    [s3_api]
    s3_region = "%s"
    api_bind_addr = "[::]:3900"
    root_domain = "%s"

    [s3_web]
    bind_addr = "[::]:3902"
    root_domain = "%s"
    index = "index.html"

    [admin]
    api_bind_addr = "[::]:3903"
  ||| % [replicationFactor, s3Region, s3RootDomain, webRootDomain];

  kurly.stateful(name, image)
  + kurly.version(version)
  // The image is a bare static binary on scratch and declares no USER, so
  // runAsNonRoot has no uid to admit against; pin one, and its fsGroup makes the
  // metadata and data directories writable to it.
  + kurly.runAs(1000)
  + kurly.port(3900)
  + kurly.extraPort('web', 3902)
  + kurly.extraPort('admin', 3903)
  // The RPC port is how nodes reach each other; it is on the Service so a second
  // node in another namespace or cluster has an address to be told about.
  + kurly.extraPort('rpc', 3901)
  // Metadata (an LMDB index of every object) and data (the blocks themselves)
  // share one volume: Garage keeps them apart on separate disks where the
  // metadata deserves an SSD, which is a claim per directory a consumer composes
  // rather than a default that would ask every cluster for two volumes.
  + kurly.store('/var/lib/garage', storageSize, storageClass=storageClass)
  // Garage reads /etc/garage.toml, so the file is mounted BY SUBPATH into /etc
  // rather than as a directory: a directory mount there would replace the image's
  // own /etc, taking the CA bundle with it.
  + kurly.config({ 'garage.toml': if config == null then defaultConfig else config }, mountPath='/etc', subPath=true)
  // GARAGE_RPC_SECRET comes from the consumer's Secret; kurly authors no Secret.
  // Any other GARAGE_* override (an admin token, a metrics token) rides in the
  // same Secret without this workload having to know the name.
  + kurly.envFromSecret(secretName)
  + kurly.env(env)
  // Readiness is the S3 port accepting a connection: every path Garage serves is
  // an S3 API call answering 4xx without a signature, and a probe that reads the
  // status code would kill a healthy node forever.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + {
    // The stateful kind's headless Service advertises port 80; make it the S3
    // port so a client reaches the node at <pod>.<name>-headless:3900, the
    // endpoint an S3 configuration points at.
    service+: {
      spec+: { ports: [
        { name: 's3', port: 3900, targetPort: 'http', protocol: 'TCP' },
        { name: 'rpc', port: 3901, targetPort: 'rpc', protocol: 'TCP' },
        { name: 'web', port: 3902, targetPort: 'web', protocol: 'TCP' },
        { name: 'admin', port: 3903, targetPort: 'admin', protocol: 'TCP' },
      ] },
    },
  }
