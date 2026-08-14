// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// shkeeper — a cryptocurrency payment gateway you run yourself: it watches for
// payments, credits invoices and calls your shop back, with no processor between
// you and the chain. A plain composable kurly.http workload. Import it and render
// with kurly.list:
//
//   local shkeeper = import 'github.com/metio/kurly/workloads/shkeeper/server.libsonnet';
//   kurly.list(shkeeper(secretName='shkeeper'))
//
// Serves the merchant interface and its API on :5000 — compose an exposure onto
// it.
//
// IT TAKES NO PAYMENTS UNTIL A NODE ANSWERS IT. Each currency is a separate
// backend — a Bitcoin, Litecoin or Monero daemon with its own chain data, which
// is hundreds of gigabytes and days of sync — and this recipe carries none of
// them. What it renders is the gateway; `backends` points it at whatever nodes
// exist, and with none configured it starts and accepts nothing.
//
// THE WALLET KEYS ARE THE MONEY. Whatever holds this instance's credentials can
// move funds, so the Secret is the whole security boundary here and an exposure
// without authentication in front is an open till.
//
// Single writer: one database and the wallet state on one ReadWriteOnce volume,
// so one replica, recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='shkeeper',
  image=defaultImage,
  storageSize='20Gi',
  storageClass=null,
  // A Secret carrying the instance's credentials and API keys.
  secretName=null,
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(5000)
  + kurly.servicePort(5000)
  + kurly.env(env)
  + (if secretName != null then kurly.envFromSecret(secretName) else {})
  // The image runs as root and owns nothing that needs it; fsGroup makes the
  // database and the wallet state writable.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/shkeeper.io/instance', storageSize, storageClass=storageClass)
  // gunicorn writes its worker temp files here.
  + kurly.scratch('/tmp', '256Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
