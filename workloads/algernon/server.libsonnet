// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// algernon — an Algernon server (a self-contained web server that serves static
// files, Markdown and Lua scripts, with templates and a built-in database). A
// plain composable kurly.http workload: the served directory and the Bolt
// database live on one PersistentVolume, so it needs nothing external. Import it
// and render with kurly.list:
//
//   local algernon = import 'github.com/metio/kurly/workloads/algernon/server.libsonnet';
//   kurly.list(algernon())
//
// Serves on :3000 — compose an exposure onto it.
//
// THE IMAGE'S OWN ENTRYPOINT IS REPLACED. The published `prod` entrypoint serves
// HTTPS on :443 from a certificate at /etc/algernon/cert.pem and redirects :80,
// which means a workload that will not start until somebody puts a keypair in the
// image's second volume — TLS in a cluster is terminated by the exposure, not by
// the application. The command here is the same server in plain HTTP mode, with
// the port and the database file stated, so `kurly.expose.*` in front of it is
// all that is needed.
//
// The served directory is EMPTY on a fresh volume and Algernon answers with a
// directory listing until you put something there: this workload carries no site.
// Content goes under `www/` on the volume (or compose a kurly.config onto it and
// point `contentPath` at the mount).
//
// Single writer: the Bolt database (users, permissions, key-value data) is a file
// on a ReadWriteOnce volume, so one replica, recreated (never rolled) — two
// servers on one Bolt file is not something Bolt sorts out afterwards.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='algernon',
  image=defaultImage,
  port=3000,
  contentPath='/data/www',
  databaseFile='/data/algernon.db',
  storageSize='5Gi',
  storageClass=null,
  extraArgs=[],
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(port)
  + kurly.servicePort(port)
  // Plain HTTP, no REPL, no banner: the exposure terminates TLS and the log is
  // read by a machine. The trailing positional is [host][:port] with an empty
  // host, which is every interface — a pod that binds one address is a pod
  // nothing outside it can reach.
  + kurly.command([
    '/bin/algernon',
    '--httponly',
    '--noninteractive',
    '--nobanner',
    '--boltdb',
    databaseFile,
  ] + extraArgs + [
    contentPath,
    ':' + port,
  ])
  + (if env == {} then {} else kurly.env(env))
  // The image declares no user and carries no shell or account database, so a uid
  // is stated here: the restricted default demands a non-root one and the image
  // cannot supply it. fsGroup is what makes the volume writable for it.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // Algernon creates a temporary directory under TMPDIR at startup and exits if it
  // cannot — a read-only root filesystem without this is a pod that never serves.
  + kurly.scratch('/tmp')
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
