// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// barcodebuddy — scan a barcode and have the item added to, or consumed from,
// your Grocy inventory. A composable kurly.http workload: it keeps its own
// settings and the barcodes it has learned in a SQLite database on a
// PersistentVolume, and everything else lives in Grocy. Import it and render with
// kurly.list:
//
//   local barcodebuddy = import 'github.com/metio/kurly/workloads/barcodebuddy/server.libsonnet';
//   kurly.list(barcodebuddy(grocyUrl='http://grocy/api', secretName='barcodebuddy'))
//
// Serves the web interface on :80 — compose an exposure onto it.
//
// IT IS A FRONT END FOR GROCY AND DOES NOTHING WITHOUT ONE. `grocyUrl` points at
// a Grocy API and `secretName` carries the API key it authenticates with; kurly
// carries grocy, so the pair deploys together. Pointed at nothing, Barcode Buddy
// starts and every scan fails.
//
// THE SCANNER IS SOMEWHERE ELSE. A USB barcode reader is attached to a machine,
// not to a pod — the arrangement that works in a cluster is the web interface, a
// phone camera, or the project's own screen-reader script running beside the
// scanner and posting to this API.
//
// The image starts nginx, php-fpm and its websocket server under supervisor as
// root, so root, escalation, the runtime capabilities and a writable root
// filesystem are relaxed deliberately rather than pretended away.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='barcodebuddy',
  image=defaultImage,
  storageSize='1Gi',
  storageClass=null,
  // The Grocy API this drives, e.g. http://grocy/api.
  grocyUrl=null,
  // A Secret carrying BBUDDY_API_KEY — the Grocy API key.
  secretName=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env(
    (if grocyUrl != null then { BBUDDY_API_URL: grocyUrl } else {})
    + env
  )
  // See the header: supervisor starts nginx, php-fpm and the websocket server as
  // root before they drop privileges.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  + kurly.writableRootFilesystem()
  + kurly.store('/config', storageSize, storageClass=storageClass)
  + (if secretName != null then kurly.envFromSecret(secretName) else {})
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
