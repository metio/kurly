// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// versity-s3-gateway — puts an S3 API in front of an ordinary filesystem, so
// tools that speak S3 can read and write a PersistentVolume. A plain composable
// kurly.http workload: the gateway itself is stateless and every object is a file
// on the volume it serves. Import it and render with kurly.list:
//
//   local versitygw = import 'github.com/metio/kurly/workloads/versity-s3-gateway/gateway.libsonnet';
//   kurly.list(versitygw(secretName='versitygw'))
//
// Serves the S3 API on :7070 — compose an exposure onto it, and note that S3
// clients using virtual-host addressing need a wildcard hostname; path-style
// addressing is what works behind a single name.
//
// THE VOLUME IS THE BUCKET NAMESPACE. A top-level directory under the served path
// is a bucket, and the objects in it are files. That is what makes this useful —
// data written through S3 stays readable as ordinary files, and files put there
// by something else appear as objects — and it is also the constraint: object
// keys have to be legal paths, and the filesystem's own limits become the
// gateway's.
//
// ROOT CREDENTIALS: `secretName` carries ROOT_ACCESS_KEY and ROOT_SECRET_KEY, the
// account that can do anything through the gateway. It is the equivalent of a
// root account rather than a user, so it belongs in a Secret and not in an
// application's configuration.
//
// Single writer: one ReadWriteOnce volume, so one replica, recreated (never
// rolled). A ReadWriteMany volume allows several gateways, and whether concurrent
// writers are safe is then a question about that filesystem, not about this
// stage.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './gateway.image', '\n');

function(
  name='versity-s3-gateway',
  image=defaultImage,
  storageSize='100Gi',
  storageClass=null,
  accessModes=['ReadWriteOnce'],
  // A Secret carrying ROOT_ACCESS_KEY and ROOT_SECRET_KEY.
  secretName=null,
  // The region the gateway reports to clients.
  region='us-east-1',
  env={},
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(7070)
  + kurly.servicePort(7070)
  + kurly.env({
    VGW_BACKEND: 'posix',
    VGW_BACKEND_ARG: '/data',
    VGW_PORT: ':7070',
    VGW_REGION: region,
  } + env)
  // The image runs as root by default; nothing in it is owned by a runtime user,
  // so an unprivileged uid with fsGroup over the served volume serves.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, accessModes=accessModes, storageClass=storageClass)
  + kurly.scratch('/tmp', '128Mi')
  + (if secretName != null then kurly.envFromSecret(secretName) else {})
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
