// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// yt-dlp-web-ui — a yt-dlp Web UI server (a browser front end for yt-dlp: paste a
// URL, pick a format, watch the download progress, and fetch the file). A plain
// composable kurly.http workload; downloads land on a PersistentVolume. Import it
// and render with kurly.list:
//
//   local ytdlp = import 'github.com/metio/kurly/workloads/yt-dlp-web-ui/server.libsonnet';
//   kurly.list(ytdlp())
//
// Serves the UI and its API on :3033 — compose an exposure onto it.
//
// IT DOWNLOADS WHATEVER IT IS ASKED TO, from wherever the pod can reach. There is
// no authentication unless you configure one, so an exposed instance is an open
// downloader running inside your network — worth an authenticating proxy, and
// worth thinking about what egress the pod has. A NetworkPolicy composed onto it
// is the other half of that.
//
// Single writer: downloads land on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='yt-dlp-web-ui',
  image=defaultImage,
  // Sized for the downloads, which is the only thing here that grows.
  storageSize='50Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3033)
  + kurly.servicePort(3033)
  + (if env == {} then {} else kurly.env(env))
  // The image never selects an account and needs nothing root provides.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // The image's own entrypoint already passes --out /downloads, so the volume goes
  // there and no argument has to be overridden.
  + kurly.store('/downloads', storageSize, storageClass=storageClass)
  // yt-dlp stages each download as a temporary file before muxing it, and ffmpeg
  // works there too.
  + kurly.scratch('/tmp')
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
