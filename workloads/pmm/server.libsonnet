// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// pmm — Percona Monitoring and Management: the server half of a database
// monitoring system, collecting metrics and query analytics from agents running
// beside MySQL, PostgreSQL and MongoDB instances and showing them in dashboards
// built for those databases. A composable kurly.http workload. Import it and
// render with kurly.list:
//
//   local pmm = import 'github.com/metio/kurly/workloads/pmm/server.libsonnet';
//   kurly.list(pmm(secretName='pmm'))
//
// Serves on :8080 — compose an exposure onto it.
//
// IT IS THE SERVER, AND THE AGENTS ARE SOMEWHERE ELSE. PMM sees nothing until a
// pmm-agent is installed beside each database and registered against this server,
// which happens from the database's side rather than from here. A PMM with no
// agents is a working set of empty dashboards.
//
// EVERYTHING LIVES IN ONE DIRECTORY, INCLUDING THE DATABASES IT RUNS. The image
// bundles VictoriaMetrics for the metrics, PostgreSQL for its own inventory and
// ClickHouse for query analytics, and puts all of them under /srv on one volume —
// so the volume is the whole deployment and its size is a retention decision
// rather than an afterthought.
//
// THE ADMIN PASSWORD IS READ ONCE, at first start, and lives in PMM's own database
// from then on. Changing the Secret afterwards changes nothing.
//
// Single writer: several databases in one directory on a ReadWriteOnce volume, so
// one replica, recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='pmm',
  image=defaultImage,
  // Metrics, query analytics and PMM's own inventory, all under /srv.
  storageSize='100Gi',
  storageClass=null,
  // A Secret carrying PMM_ADMIN_PASSWORD, read once at first start.
  secretName='pmm',
  // How long metrics are kept, e.g. '30d'.
  retention=null,
  env={},
  resources={ requests: { cpu: '1', memory: '4Gi' }, limits: { memory: '8Gi' } },
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
    (if retention != null then { PMM_DATA_RETENTION: retention } else {})
    + env
  )
  // The uid the image already runs as; fsGroup so the bundled databases can write
  // under /srv.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/srv', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '1Gi')
  + (if secretName != null then kurly.envFromSecret(secretName) else {})
  // Several databases are initialised on the first start, which takes minutes; a
  // shorter budget restarts the pod in the middle of it.
  + kurly.startupProbe({ httpGet: { path: '/v1/readyz', port: 'http' }, periodSeconds: 10, failureThreshold: 60 })
  + kurly.readinessProbe({ httpGet: { path: '/v1/readyz', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
