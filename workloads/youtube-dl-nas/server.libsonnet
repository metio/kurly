// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// youtube-dl-nas — a youtube-dl-nas server (a password-protected web queue that
// hands URLs to yt-dlp and keeps the resulting video, audio and subtitle files,
// with a download history). A plain composable kurly.http workload keeping the
// downloads and its queue/history state on two PersistentVolumes. Import it and
// render with kurly.list:
//
//   local ytdlnas = import 'github.com/metio/kurly/workloads/youtube-dl-nas/server.libsonnet';
//   kurly.list(ytdlnas())
//
// Serves the queue interface and API on :8080 — compose an exposure onto it.
//
// The entrypoint runs as root: it substitutes the credentials into Auth.json
// beside its own code, chowns the two volumes, and only then drops to PUID:PGID
// with gosu. That is the whole reason for the relaxations here — root, a
// writable root filesystem, privilege escalation and the capabilities the chown
// needs. Set PUID/PGID through env to have the files themselves owned by an
// unprivileged account.
//
// Both auto-updaters are off by default. yt-dlp's would pip-install into the
// image's site-packages on every start and write a log under /var/log, and the
// subtitle-QA one installs a further package — a container that reaches the
// internet to change itself at boot is not what an air-gapped or allow-listed
// cluster deploys. Turn YTDLP_AUTO_UPDATE back on where keeping pace with
// YouTube's extractor changes matters more, and expect the egress.
//
// It downloads from the public internet, so the pod needs egress even though
// nothing else here does — a NetworkPolicy that forgets it leaves every job
// failing.
//
// Single writer: one queue and one history file on ReadWriteOnce volumes, so one
// replica, recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='youtube-dl-nas',
  image=defaultImage,
  // The downloaded media. Sized for what a real queue accumulates rather than
  // for the application itself, which needs almost nothing.
  downloadSize='50Gi',
  // The queue, the download history and the login sessions.
  stateSize='1Gi',
  storageClass=null,
  // The Secret holding MY_ID and MY_PW, the single account that may reach the
  // queue. There is no other authentication and no way to run without one: the
  // server refuses to start when either is unset.
  secretName='youtube-dl-nas',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env({
    APP_PORT: '8080',
    YTDLP_AUTO_UPDATE: 'false',
    NLPTUTTI_AUTO_UPDATE: 'false',
  } + env)
  + kurly.envFromSecret(secretName)
  // The entrypoint is root until it has rewritten Auth.json and chowned the
  // volumes; gosu then drops to PUID:PGID for the server itself.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  // Auth.json is rewritten in place inside the install tree, through a temporary
  // file in the same directory — a read-only root filesystem fails the container
  // before the server is reached.
  + kurly.writableRootFilesystem()
  + kurly.store('/downfolder', downloadSize, storageClass=storageClass)
  + kurly.store('/usr/src/app/metadata', stateSize, storageClass=storageClass)
  + kurly.scratch('/tmp')
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
