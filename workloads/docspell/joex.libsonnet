// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// docspell/joex — the Docspell job executor: it takes every uploaded document off
// the queue and converts, OCRs, classifies and indexes it. A composable kurly.http
// workload sharing the server stage's PostgreSQL. Import it and render with
// kurly.list:
//
//   local joex = import 'github.com/metio/kurly/workloads/docspell/joex.libsonnet';
//   kurly.list(joex())
//
// It is a kurly.http workload rather than a worker because it is ADDRESSED: a joex
// node registers its own base URL in the database and the REST server calls back to
// it (to cancel a job, or to ask what it is doing), so it needs a Service and a URL
// that resolves to it. Do not expose it — nothing outside the namespace calls it.
//
// baseUrl must be THIS stage's own Service. It is what the node publishes to the
// rest of the cluster, so a wrong value leaves jobs running that the UI cannot stop.
//
// ONE NODE PER app-id. Docspell identifies a job executor by `app-id`, and two nodes
// sharing one confuse the registry, so scaling out means rendering this stage again
// with a different name and appId rather than raising replicas.
//
// It carries the conversion toolchain (Tesseract, Ghostscript, LibreOffice,
// unpaper, ocrmypdf), all of which want a temporary directory and a HOME — hence
// the scratch at /tmp and HOME pointed at it. Give it real memory: OCR of a large
// scan is the heaviest thing a Docspell installation does.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './joex.image', '\n');

function(
  name='docspell-joex',
  image=defaultImage,
  // The URL this node publishes for the REST server to call back on — its own Service.
  baseUrl='http://docspell-joex:7878',
  // Unique per job executor node.
  appId='joex1',
  // The same PostgreSQL the server stage uses.
  jdbcUrl='jdbc:postgresql://docspell-db-rw:5432/docspell',
  dbUser='docspell',
  // The Secret holding DOCSPELL_JOEX_JDBC_PASSWORD (kurly mints none), via envFrom.
  secretName='docspell',
  // How many jobs this node runs at once.
  poolSize=1,
  env={},
  resources={ requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '3Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.port(7878)
  + kurly.servicePort(7878)
  + kurly.env(
    {
      DOCSPELL_JOEX_APP__ID: appId,
      DOCSPELL_JOEX_BASE__URL: baseUrl,
      DOCSPELL_JOEX_BIND_ADDRESS: '0.0.0.0',
      DOCSPELL_JOEX_BIND_PORT: '7878',
      DOCSPELL_JOEX_JDBC_URL: jdbcUrl,
      DOCSPELL_JOEX_JDBC_USER: dbUser,
      DOCSPELL_JOEX_SCHEDULER_POOL__SIZE: std.toString(poolSize),
      // LibreOffice and unoconv refuse to start without a writable HOME.
      HOME: '/tmp',
    } + env
  )
  + kurly.envFromSecret(secretName)
  // The image runs as root; neither the JVM nor the conversion tools need to, and
  // the hardened default refuses a container that would.
  + kurly.runAs(1000, gid=1000)
  // Every conversion writes its intermediate files under java.io.tmpdir; a scratch
  // there keeps the root filesystem read-only. Raise sizeLimit for large scans.
  + kurly.scratch('/tmp', sizeLimit='2Gi')
  // A Service named after this workload makes Kubernetes inject DOCSPELL_JOEX_PORT
  // as `tcp://…`, which is exactly the config key Docspell reads its listen port from.
  + kurly.disableServiceLinks()
  + kurly.startupProbe({ httpGet: { path: '/api/info/version', port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ httpGet: { path: '/api/info/version', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/info/version', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
