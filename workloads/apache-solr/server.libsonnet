// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// apache-solr — an Apache Solr server (the search platform on top of Lucene:
// full-text indexing, faceting, filtering and highlighting over an HTTP/JSON
// API). A plain composable kurly.http workload on the official image; cores and
// indexes live on a PersistentVolume and it needs nothing external. Import it
// and render with kurly.list:
//
//   local solr = import 'github.com/metio/kurly/workloads/apache-solr/server.libsonnet';
//   kurly.list(solr())
//
// Serves the API and the admin UI on :8983.
//
// Solr ships with no authentication until a security.json is put in place, so it
// answers whoever reaches it — including the admin UI, which can create and drop
// collections. Keep it inside the cluster and reach it from your own
// application, or authenticate in front of it; an exposure alone publishes an
// unauthenticated index.
//
// Single writer: one index directory on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two Solr processes off the same files. This is
// the standalone server; SolrCloud is a different topology and not what this
// stage renders.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='apache-solr',
  image=defaultImage,
  // Cores, indexes and Solr's own logs all live under /var/solr.
  storageSize='10Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '250m', memory: '1Gi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8983)
  + kurly.servicePort(8983)
  + (if env == {} then {} else kurly.env(env))
  // A Service named after this workload makes Kubernetes inject SOLR_PORT as
  // `tcp://10.x.x.x:8983` — and `bin/solr` reads SOLR_PORT as the port to LISTEN
  // on, so the injected URL is parsed as a port number and the server never
  // comes up. Nothing here needs the links.
  + kurly.disableServiceLinks()
  // The image builds a `solr` account (uid 8983) and its entrypoint only chowns
  // /var/solr when it starts as root. Naming that account skips the chown, so the
  // restricted posture holds and fsGroup is what makes the volume writable.
  + kurly.runAs(8983, gid=8983, fsGroup=8983)
  + kurly.store('/var/solr', storageSize, storageClass=storageClass)
  // The JVM unpacks and writes temporary files beside its own install tree.
  + kurly.scratch('/tmp')
  // A cold JVM plus core discovery takes well past a liveness probe's patience,
  // and the admin API answers 404 until Solr has finished loading — so the wait
  // belongs in a startup probe rather than in a longer liveness delay.
  + kurly.startupProbe({ httpGet: { path: '/solr/admin/info/system', port: 'http' }, failureThreshold: 30, periodSeconds: 5 })
  + kurly.readinessProbe({ httpGet: { path: '/solr/admin/info/system', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/solr/admin/info/system', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
