// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// yacy — a YaCy search server (a peer-to-peer web search engine: it crawls and
// indexes itself and, unless you tell it otherwise, joins the public network of
// peers and answers their queries too). A plain composable kurly.http workload:
// the crawler queues, the Solr index and the peer's own identity all live in one
// DATA directory on a PersistentVolume. Import it and render with kurly.list:
//
//   local yacy = import 'github.com/metio/kurly/workloads/yacy/server.libsonnet';
//   kurly.list(yacy())
//
// Serves the search page and the administration interface on :8090 — compose an
// exposure onto it.
//
// THE ADMINISTRATION INTERFACE HAS NO PASSWORD UNTIL YOU SET ONE. YaCy ships an
// `admin` account with an empty password and only limits it to local access; a
// pod's "local" is anything that reaches the container. Set the password from
// /ConfigAccounts_p.html on first login, before composing an exposure, or put an
// authenticating proxy in front.
//
// Single writer: one index directory on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) — two JVMs on one Solr index corrupt it.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='yacy',
  image=defaultImage,
  // The index grows with what you crawl, and it only grows — start well above
  // what the first crawl needs.
  storageSize='20Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8090)
  + kurly.servicePort(8090)
  + (if env == {} then {} else kurly.env(env))
  // The image's own `yacy` account is a system user (uid 100, gid 101) named as
  // text, which kubelet cannot check against runAsNonRoot — pin it numerically,
  // and its fsGroup makes the DATA volume writable.
  + kurly.runAs(100, gid=101, fsGroup=101)
  // The whole of YaCy's state — index, crawl queues, peer identity, the settings
  // written from the web interface — is one directory inside the install tree.
  + kurly.store('/opt/yacy_search_server/DATA', storageSize, storageClass=storageClass)
  // The JVM writes its perf-data and temporary files under /tmp; the rest of the
  // root filesystem stays read-only.
  + kurly.scratch('/tmp', '512Mi')
  // Kubernetes injects YACY_PORT as `tcp://…` for a Service named after the
  // workload, and a Java process reading its own environment for configuration
  // has no reason to expect that.
  + kurly.disableServiceLinks()
  // A JVM unpacking its Solr cores and rebuilding the index the first time takes
  // minutes; give it the budget up front instead of a lenient liveness probe that
  // stays lenient forever.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 60 })
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
