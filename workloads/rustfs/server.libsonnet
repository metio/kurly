// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// rustfs — an S3-compatible object store written in Rust: buckets and objects on
// a PersistentVolume, spoken to over the S3 API by anything that already speaks
// it. A plain composable kurly.http workload. Import it and render with
// kurly.list:
//
//   local rustfs = import 'github.com/metio/kurly/workloads/rustfs/server.libsonnet';
//   kurly.list(rustfs(secretName='rustfs'))
//
// Serves the S3 API on :9000 and the console on :9001 — compose an exposure onto
// the API, and note that S3 clients using virtual-host addressing need a wildcard
// hostname while path-style addressing works behind a single name.
//
// THE DEFAULT CREDENTIALS ARE PUBLISHED IN THE PROJECT'S OWN DOCUMENTATION.
// Without a Secret the image starts with rustfsadmin/rustfsadmin, which is the
// same on every deployment anybody has ever run — `secretName` carries
// RUSTFS_ACCESS_KEY and RUSTFS_SECRET_KEY, and an instance reachable by anyone
// else needs them before it is reachable, not after.
//
// IT IS A RELEASE CANDIDATE, AND ITS DISTRIBUTED MODE IS NOT DONE. Upstream marks
// distributed operation, lifecycle rules and KMS as under test; what this recipe
// renders is the single-node shape, which is the part they call ready. Treat it
// accordingly for data you cannot lose.
//
// Single writer: one volume holding every bucket, so one replica, recreated
// (never rolled) — two processes over one object store's on-disk format is how
// it gets corrupted.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='rustfs',
  image=defaultImage,
  storageSize='100Gi',
  storageClass=null,
  // A Secret carrying RUSTFS_ACCESS_KEY and RUSTFS_SECRET_KEY.
  secretName=null,
  logLevel='warn',
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(9000)
  + kurly.servicePort(9000)
  + kurly.extraPort('console', 9001)
  + kurly.env(
    {
      RUSTFS_VOLUMES: '/data',
      RUSTFS_ADDRESS: '0.0.0.0:9000',
      RUSTFS_CONSOLE_ADDRESS: '0.0.0.0:9001',
      RUSTFS_OBS_LOGGER_LEVEL: logLevel,
      // The image writes its logs to a directory rather than stdout, and that
      // directory is on the read-only root filesystem; /tmp is the scratch below.
      RUSTFS_OBS_LOG_DIRECTORY: '/tmp/logs',
    }
    + env
  )
  + (if secretName != null then kurly.envFromSecret(secretName) else {})
  // The uid and gid the image's own rustfs user carries; fsGroup so the volume is
  // writable by it.
  + kurly.runAs(10001, gid=10001, fsGroup=10001)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '512Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
