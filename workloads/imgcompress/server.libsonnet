// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// imgcompress — an imgcompress server (compresses, converts, resizes and batch
// processes images through a web interface, including HEIC/WebP/PDF conversion and
// background removal that runs on this pod rather than in somebody else's cloud).
// A plain composable kurly.http workload. Import it and render with kurly.list:
//
//   local imgcompress = import 'github.com/metio/kurly/workloads/imgcompress/server.libsonnet';
//   kurly.list(imgcompress())
//
// Serves the web app and its API on :5000 — compose an exposure onto it.
//
// NOTHING IS PERSISTED. Uploads and results live in a temporary directory the app
// sweeps an hour after they were written, so there is no PersistentVolume here and
// nothing to back up — a restart loses whatever a user has not downloaded yet.
// That directory is a scratch volume rather than the container filesystem, and it
// is the one thing worth sizing: it holds every uploaded image and every rendered
// output at once, and the app accepts a 40 GiB upload by default.
//
// One replica: a download link names the temporary folder the run wrote, and only
// the pod that made it can serve the files back. A second replica would answer
// half the downloads with a 404.
//
// The image is a Debian-based distroless with no shell, running as its own
// unprivileged account (65532), so nothing about privileges is relaxed here. The
// root filesystem is writable for one reason: the entrypoint writes a runtime.json
// into the frontend's own config directory before the server starts, and a
// read-only filesystem is the difference between starting and not. The path is too
// long to name a volume after (a volume name is a DNS label, and it is 69
// characters), so it cannot be carved out with a scratch mount the way /tmp is.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='imgcompress',
  image=defaultImage,
  // The working directory for uploads and results. Everything a user submits
  // passes through it, so size it for the largest batch you want to allow.
  tempSize='4Gi',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { cpu: '2', memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.port(5000)
  + kurly.servicePort(5000)
  + (if env == {} then {} else kurly.env(env))
  // The image declares USER nonroot (65532); naming it keeps the pod admissible
  // under the restricted profile and makes the scratch volume writable.
  + kurly.runAs(65532, gid=65532, fsGroup=65532)
  + kurly.scratch('/tmp', tempSize)
  // The entrypoint writes the frontend's runtime.json inside the image's own tree
  // on every start, and that path is too long to name a volume after.
  + kurly.writableRootFilesystem()
  // The health endpoint answers without authentication and does not redirect.
  // granian forks a worker per CPU before it serves anything, and on a busy node
  // that takes longer than a liveness probe's patience — the container is killed
  // mid-startup and restarts into the same race forever. A startup probe is what
  // holds liveness off until the socket answers once.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 5, failureThreshold: 60 })
  + kurly.readinessProbe({ httpGet: { path: '/api/health/backend', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/health/backend', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
