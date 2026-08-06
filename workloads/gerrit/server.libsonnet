// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// gerrit — a Gerrit Code Review server (git hosting where every push becomes a
// change others vote on before it lands). A plain composable kurly.http workload
// on the official image. Import it and render with kurly.list:
//
//   local gerrit = import 'github.com/metio/kurly/workloads/gerrit/server.libsonnet';
//   kurly.list(gerrit(canonicalWebUrl='https://review.example.com/'))
//
// Serves the web UI and git-over-HTTP on :8080 and git-over-SSH on :29418 —
// compose an exposure onto the HTTP port, and route TCP :29418 for SSH.
//
// STORAGE: the site directory /var/gerrit also holds the installed program
// (bin/gerrit.war, lib), so one volume over the whole site would hide it. The
// four directories that must survive a restart get one PVC each — the
// repositories (git), the site configuration and its keys (etc), the Lucene
// index (index) and the H2 databases (db) — while the regenerable ones (cache,
// logs, tmp, data, static) are scratch. Gerrit does not rebuild an index it
// cannot find: it refuses to start.
//
// CANONICAL URL: Gerrit writes gerrit.canonicalWebUrl on every start, from
// CANONICAL_WEB_URL or, absent that, from the pod's hostname — which changes
// with every pod and leaves the links, clone commands and e-mails pointing at a
// name nobody can resolve. Set canonicalWebUrl to the address people reach it
// at as soon as there is one.
//
// FIRST START IS LONG: the entrypoint initialises the site, installs every
// bundled plugin and builds the index before it serves. The startup probe
// carries that wait rather than a stretched liveness delay.
//
// AUTHENTICATION: the batch init leaves auth.type at OpenID, which is an open
// door on a public address. Decide the authentication before publishing it — an
// authenticating proxy in front (auth.type HTTP) or an OAuth/LDAP provider
// configured in etc/gerrit.config.
//
// Single writer: the repositories and the H2 databases sit on ReadWriteOnce
// volumes, so this is one replica, recreated (never rolled) — two servers
// writing one repository is not something git sorts out afterwards.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='gerrit',
  image=defaultImage,
  // One PVC per directory of the site that must survive a restart.
  storageSize='20Gi',
  indexSize='5Gi',
  dbSize='2Gi',
  etcSize='1Gi',
  storageClass=null,
  // The address people reach this Gerrit at, written to gerrit.canonicalWebUrl on
  // every start. Left null, Gerrit uses the pod's hostname.
  canonicalWebUrl=null,
  env={},
  resources={ requests: { cpu: '500m', memory: '2Gi' }, limits: { memory: '4Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    // The port the image binds; the entrypoint writes it to httpd.listenUrl, so the
    // declared port and the served port cannot drift apart.
    HTTPD_LISTEN_URL: 'http://*:8080/',
    // The launcher unpacks the war's jars before it runs anything, into
    // $HOME/.gerritcodereview/tmp unless told otherwise — and $HOME here is
    // /var/gerrit, which is the image's own read-only tree. Without this the
    // process dies on an IOException before it has read a line of configuration.
    GERRIT_TMP: '/var/gerrit/tmp',
  } + (if canonicalWebUrl == null then {} else { CANONICAL_WEB_URL: canonicalWebUrl });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.extraPort('ssh', 29418)
  + kurly.env(baseEnv + env)
  // The image declares USER gerrit (uid 1000) and drops no privileges itself; pin
  // the uid and its fsGroup so the volumes are writable under the restricted
  // posture.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // The site's persistent halves. /var/gerrit itself stays the image's, so
  // bin/gerrit.war and lib survive the mounts.
  + kurly.store('/var/gerrit/git', storageSize, storageClass=storageClass)
  + kurly.store('/var/gerrit/index', indexSize, storageClass=storageClass)
  + kurly.store('/var/gerrit/db', dbSize, storageClass=storageClass)
  + kurly.store('/var/gerrit/etc', etcSize, storageClass=storageClass)
  // The regenerable halves, so the root filesystem stays read-only.
  + kurly.scratch('/var/gerrit/cache')
  + kurly.scratch('/var/gerrit/logs')
  + kurly.scratch('/var/gerrit/tmp')
  + kurly.scratch('/var/gerrit/data')
  + kurly.scratch('/var/gerrit/static')
  + kurly.scratch('/var/gerrit/plugins')
  + kurly.scratch('/tmp', '256Mi')
  // A Service named gerrit makes Kubernetes inject GERRIT_PORT as a tcp:// URL
  // into the very process that reads GERRIT_* for its own settings.
  + kurly.disableServiceLinks()
  // Site init, plugin installation and the first index build all happen before the
  // first request is answered.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 90 })
  // /config/server/version answers 200 without a session; the UI root redirects
  // through the login flow once authentication is configured.
  + kurly.readinessProbe({ httpGet: { path: '/config/server/version', port: 'http' }, periodSeconds: 15 })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
