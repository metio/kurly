// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// pydio-cells — a file sharing and collaboration platform: workspaces, sharing
// links, versioning and an activity feed over storage you own. A plain composable
// kurly.http workload: the files and Cells' own configuration live under
// CELLS_WORKING_DIR on a PersistentVolume, with the metadata in an external
// MySQL/MariaDB. Import it and render with kurly.list:
//
//   local cells = import 'github.com/metio/kurly/workloads/pydio-cells/server.libsonnet';
//   kurly.list(cells(externalUrl='https://files.example.com'))
//
// Serves the web app and API on :8080 — compose an exposure onto it.
//
// IT CONFIGURES ITSELF ON FIRST START, THROUGH A WIZARD. The image's entrypoint
// checks whether Cells is installed and, if not, turns `cells start` into `cells
// configure` — so the first request lands on a setup form that asks for the
// database and the first administrator, and the probes here are by connection
// rather than a path that does not answer yet. Nothing is stored until somebody
// completes it.
//
// TLS TERMINATES IN FRONT OF IT. Cells enables TLS on its own site by default and
// then wants a certificate before it will answer; `CELLS_SITE_NO_TLS` is set so
// the exposure in front holds the certificate instead, which is the arrangement a
// cluster deployment wants.
//
// EXTERNAL URL: `externalUrl` is what Cells puts in share links and OAuth
// redirects. Left unset it uses whatever it can infer, and the links it hands out
// resolve only from inside the cluster.
//
// Single writer: one working directory on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='pydio-cells',
  image=defaultImage,
  storageSize='100Gi',
  storageClass=null,
  // The URL a browser reaches this at; Cells builds share links from it.
  externalUrl=null,
  env={},
  resources={ requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env(
    {
      CELLS_WORKING_DIR: '/var/cells',
      CELLS_SITE_BIND: '0.0.0.0:8080',
      CELLS_SITE_NO_TLS: '1',
    }
    + (if externalUrl != null then { CELLS_SITE_EXTERNAL: externalUrl } else {})
    + env
  )
  // The image runs as root and carries no user of its own; everything Cells
  // writes is under the working directory, which fsGroup makes writable, so an
  // unprivileged uid keeps the hardened posture.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/var/cells', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '1Gi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
