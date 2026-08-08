// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// zenko-cloudserver — a Zenko CloudServer node (an S3-compatible object storage
// server: it speaks the S3 API and keeps the objects on local disk, or forwards
// them to a cloud bucket). A plain composable kurly.http workload on the official
// image, serving S3 on :8000. Import it and render with kurly.list:
//
//   local cloudserver = import 'github.com/metio/kurly/workloads/zenko-cloudserver/server.libsonnet';
//   kurly.list(cloudserver(endpoint='s3.example.com', storageSize='200Gi'))
//
// THE ENDPOINT IS PART OF THE CONTRACT, NOT COSMETICS. CloudServer answers only
// for host names it was told about: a request whose Host header is not a
// configured REST endpoint is refused, so `endpoint` must be the name clients
// actually address it by — the in-cluster Service name when it is consumed from
// the cluster, the public name when an exposure is composed in front of it. The
// image's entrypoint accepts exactly ONE, which is why this is a string and not
// a list; several endpoints are a `config.json` a consumer mounts over.
//
// IT REWRITES ITS OWN CONFIG FILE ON EVERY START. The entrypoint reads the
// environment, edits /usr/src/app/config.json in place with jq, and exits
// non-zero if it cannot — beside its own code, as root, which is why this
// workload runs with a writable root filesystem and the root user rather than
// the hardened default. Neither is optional: a read-only rootfs stops the
// container before it serves, and the file is root-owned.
//
// Credentials are the S3 account, not a login: SCALITY_ACCESS_KEY_ID and
// SCALITY_SECRET_ACCESS_KEY come from a Secret the consumer provides, and they
// are what an S3 client signs with. kurly authors no Secret.
//
// Data and metadata are SEPARATE volumes, because that is how the image lays them
// out (/usr/src/app/localData holds the objects, /usr/src/app/localMetadata the
// index of them) and an operator sizing an object store wants the index somewhere
// else than the blocks.
//
// Single writer: both volumes are ReadWriteOnce and the metadata daemon runs
// inside this pod, so one replica, recreated (never rolled). Growing this is a
// second CloudServer against shared metadata, not a replica count.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='zenko-cloudserver',
  image=defaultImage,
  endpoint='zenko-cloudserver',
  region='us-east-1',
  backend='file',
  logLevel='info',
  dataSize='50Gi',
  metadataSize='10Gi',
  storageClass=null,
  secretName='zenko-cloudserver',
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  // One writer: the metadata daemon runs in this pod and owns the index on a
  // ReadWriteOnce volume, so a rolling update would deadlock on the mount.
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8000)
  + kurly.servicePort(8000)
  + kurly.env({
    // The single REST endpoint CloudServer answers for, and the region it reports
    // for it — an S3 client that signs for a different region is refused.
    ENDPOINT: endpoint,
    REGION: region,
    // 'file' keeps objects and their index on the mounted volumes; 'mem' throws
    // everything away when the pod restarts and exists for trying it out.
    S3BACKEND: backend,
    LOG_LEVEL: logLevel,
    // The image otherwise registers with Scality's hosted Orbit management
    // service and keeps a connection open to it. A workload does not phone home
    // from a cluster unless somebody asked it to.
    REMOTE_MANAGEMENT_DISABLE: '1',
  })
  + kurly.env(env)
  // SCALITY_ACCESS_KEY_ID and SCALITY_SECRET_ACCESS_KEY are the S3 account an
  // client signs with; kurly authors no Secret.
  + kurly.envFromSecret(secretName)
  // The image's own VOLUME declarations, kept apart: the objects and the index of
  // them are sized and placed independently.
  + kurly.store('/usr/src/app/localData', dataSize, storageClass=storageClass)
  + kurly.store('/usr/src/app/localMetadata', metadataSize, storageClass=storageClass)
  // The entrypoint edits config.json IN PLACE, in the image's own install tree,
  // and `set -e` stops the container when that write fails. The tree is root-owned
  // and holds node_modules, so it can be neither mounted over nor handed to an
  // unprivileged user — the two relaxations below are what make it start at all.
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  // Every S3 path validates the Host header and answers 403 without a signature,
  // and /_/healthcheck is served only to the loopback range the default config
  // allows — a probe reading a status code would kill a healthy node forever, so
  // readiness is the S3 port accepting a connection.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  // Node builds the metadata index at first start before it listens; give it room
  // to do that instead of letting liveness restart it halfway through.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 5, failureThreshold: 60 })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
