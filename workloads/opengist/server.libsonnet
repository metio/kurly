// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// opengist — an Opengist server (a self-hosted pastebin where every snippet is a
// real Git repository). A plain composable kurly.http workload: it keeps the gist
// repositories, its SQLite database and the Bleve search index on a
// PersistentVolume, so it needs no external database. Import it and render with
// kurly.list:
//
//   local opengist = import 'github.com/metio/kurly/workloads/opengist/server.libsonnet';
//   kurly.list(opengist())
//
// Serves the web UI and API on :6157 — compose an exposure onto it. Git over SSH
// is built in and listens on :2222, carried on the Service as a second port; route
// it separately (a Gateway TCPRoute, a LoadBalancer) or leave it in-cluster.
//
// Single writer: one SQLite database and one Bleve index on a ReadWriteOnce
// volume, so one replica, recreated (never rolled) to keep two pods off the files.
// Point OG_DB_URI at external PostgreSQL or MySQL through env to move the database
// off the volume — the repositories themselves stay on it either way.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='opengist',
  image=defaultImage,
  storageSize='5Gi',
  storageClass=null,
  // The server's own public URL. Clone URLs, OAuth callbacks and the links in
  // embeds are built from it, so every value is wrong somewhere else and there is
  // no default: unset, Opengist falls back to the request's host.
  externalUrl=null,
  // The Secret holding OG_SECRET_KEY, which signs session cookies. Unset,
  // Opengist generates 32 random bytes at STARTUP, so every restart logs everyone
  // out — it is supplied rather than left to the app. kurly authors no Secret.
  secretName='opengist',
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(6157)
  + kurly.servicePort(6157)
  + kurly.extraPort('ssh', 2222)
  + kurly.env(
    {
      // The image logs to stdout AND to a file under the data directory; keep the
      // volume for gists and let the container convention carry the log.
      OG_LOG_OUTPUT: 'stdout',
    }
    + (if externalUrl == null then {} else { OG_EXTERNAL_URL: externalUrl })
    + env
  )
  + kurly.envFromSecret(secretName)
  // The entrypoint runs the server directly when it is already non-root, and only
  // chowns the data directory and drops privileges with `su` when started as uid
  // 0. Pinning a non-root uid takes the first path, so the restricted posture
  // holds — no root, no privilege escalation, no capabilities — and fsGroup is
  // what makes the volume writable instead.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // The entrypoint pins OG_OPENGIST_HOME to /opengist, so this path is the
  // application's, not a choice: overriding the variable does not move the data.
  + kurly.store('/opengist', storageSize, storageClass=storageClass)
  // git writes temporary files while packing objects on push.
  + kurly.scratch('/tmp')
  // Connection probes: there is no health endpoint, and every page answers a
  // redirect to the login form once require-login is set.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
