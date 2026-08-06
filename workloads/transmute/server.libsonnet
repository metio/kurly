// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// transmute — a Transmute server (a self-hosted file converter and compressor for
// images, video, audio, documents and spreadsheets, driving ffmpeg, ImageMagick and
// friends from a web UI). A plain composable kurly.http workload on the official
// image; uploads, results and its own state live on a PersistentVolume. Import it
// and render with kurly.list:
//
//   local transmute = import 'github.com/metio/kurly/workloads/transmute/server.libsonnet';
//   kurly.list(transmute(appUrl='https://transmute.example.com'))
//
// Serves the web app on :3313 — compose an exposure onto it.
//
// APP_URL is its own public URL and there is no default that is right anywhere, so
// it is a parameter: pass the address the exposure serves, with the scheme a browser
// sees (https where the ingress terminates TLS, even though Transmute serves plain
// HTTP itself). Omitted when null.
//
// A conversion is CPU- and memory-hungry and writes the whole file twice, so the
// limits here are a starting point for small files, not a fleet default — a video
// transcode will want considerably more of both, and a store large enough to hold
// the input and the output side by side.
//
// Single writer: uploads and results live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the same files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='transmute',
  image=defaultImage,
  appUrl=null,
  storageSize='10Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  // HOME is unset in the image, so the libraries that cache beside it (fontconfig,
  // matplotlib) fall back to a path an unprivileged user cannot write, and the
  // converters that draw text fail one by one rather than at startup. Pointing both
  // at the scratch keeps the root filesystem read-only.
  local baseEnv = { HOME: '/tmp', XDG_CACHE_HOME: '/tmp/cache' }
                  + (if appUrl == null then {} else { APP_URL: appUrl });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3313)
  + kurly.servicePort(3313)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // The converters stage their intermediate files under /tmp, and a conversion is
  // exactly as large as the file it is working on — so this is sized for the files
  // you expect, not as a token amount.
  + kurly.scratch('/tmp', '2Gi')
  + kurly.store('/app/data', storageSize, storageClass=storageClass)
  // A Python backend importing the whole conversion toolchain, behind an Xvfb the
  // entrypoint starts first — several minutes before it listens on a cold node. The
  // startup budget is what keeps liveness from killing it mid-import.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 60 })
  // Its own readiness endpoint, the one the published compose file polls.
  + kurly.readinessProbe({ httpGet: { path: '/api/health/ready', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
