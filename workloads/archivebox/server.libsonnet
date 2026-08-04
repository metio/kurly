// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD
//
// archivebox — an ArchiveBox server (self-hosted web archiving: give it URLs, RSS
// feeds or bookmark exports and it keeps its own copies as HTML, PDF, screenshots
// and WARC). A plain composable kurly.http workload: the archive, its SQLite index
// and the search index all live on one PersistentVolume, so it needs nothing
// external. Import it and render with kurly.list:
//
//   local archivebox = import 'github.com/metio/kurly/workloads/archivebox/server.libsonnet';
//   kurly.list(archivebox())
//
// Serves the web UI on :8000 — compose an exposure onto it.
//
// Single writer: one SQLite index and one archive tree on a ReadWriteOnce volume,
// so one replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='archivebox',
  image=defaultImage,
  storageSize='50Gi',
  storageClass=null,
  // The uid and gid the archive is owned by and the server runs as. The entrypoint
  // reads them, chowns the data directory to match, and drops to them — so this is
  // the account that ends up owning every archived file, and changing it later
  // means a chown of the whole archive. 911 is the image's own default.
  puid=911,
  pgid=911,
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8000)
  + kurly.servicePort(8000)
  + kurly.env({ PUID: std.toString(puid), PGID: std.toString(pgid) } + env)
  // The entrypoint starts as root, usermods its own account onto PUID/PGID, chowns
  // the data directory and drops to that account with gosu. Unlike opengist and
  // cloudbeaver — whose entrypoints branch on whether they are already unprivileged
  // — this one has no such path and refuses PUID=0 outright, so root is genuinely
  // required to reach the unprivileged process it eventually runs as.
  //
  // Each relaxation buys one step of that: root to start, the capabilities gosu
  // needs to change uid, and privilege escalation so the setuid call is permitted.
  // Everything else stays: the archive is still written by an unprivileged user.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  // A read-only root filesystem kills it before it produces a single line of
  // output: the container exits 10 immediately, with empty logs, and nothing
  // anywhere names the cause. That silence is the reason this is spelled out
  // rather than left as one more relaxed knob — the same image runs perfectly with
  // the filesystem writable, so the failure looks like a broken image rather than
  // a denied write. It sets up a browser profile, a node environment and a Django
  // instance beside its own code, none of which is data worth a volume.
  + kurly.writableRootFilesystem()
  // The entrypoint chowns this directory, creates it if absent, and writes the
  // SQLite index, the archive tree and the search index into it.
  + kurly.store('/data', storageSize, storageClass=storageClass)
  // Headless Chrome — how the PDF, screenshot and singlefile extractors work —
  // will not fit in the 64MiB of shared memory a container gets by default.
  + kurly.scratch('/dev/shm', '256Mi')
  // The first start creates the SQLite schema and the archive layout before it
  // serves anything.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
