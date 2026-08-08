// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// sentryshot — a SentryShot server (a network video recorder for IP cameras).
// A plain composable kurly.http workload: cameras, accounts and the recording
// index live under /app/configs, the recordings themselves on a second volume
// at /app/storage, so it needs no external database. Import it and render with
// kurly.list:
//
//   local sentryshot = import 'github.com/metio/kurly/workloads/sentryshot/server.libsonnet';
//   kurly.list(sentryshot())
//
// Serves the web UI and API on :2020 (the UI lives at /live) — compose an
// exposure onto it.
//
// The main config is a file the app reads at start, never edits: it rides
// read-only over the /app/configs volume as a single file, leaving accounts.json
// and the monitor definitions on the volume beside it writable. Generate your
// own with the `config` parameter to enable the motion, object-detection,
// thumbnail or MQTT plugins.
//
// Bootstrapping accounts: `auth_basic` starts with an EMPTY accounts.json and
// there is no command that seeds one, so a fresh instance with basic auth has
// nobody who can log in. Deploy once with auth='none' behind an exposure only
// you can reach, create the admin account in the UI, then set auth='basic' and
// redeploy — the accounts survive on the volume.
//
// Two ReadWriteOnce volumes, so one replica, recreated (never rolled) to keep
// two pods off the recordings.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

// The app's own generated config, with the paths pinned to the mounts this
// recipe makes and every optional plugin off. `maxDiskUsageGb` is what keeps the
// recordings volume from filling: SentryShot deletes the oldest recordings
// before it is exceeded, so keep it below the volume's size.
local configFile(auth, maxDiskUsageGb) = |||
  port = 2020
  storage_dir = "/app/storage"
  config_dir = "/app/configs"
  plugin_dir = "/app/plugins"
  max_disk_usage = %(maxDiskUsage)d
  debug_log_stdout = false

  [[plugin]]
  name = "auth_basic"
  enable = %(basic)s

  [[plugin]]
  name = "auth_none"
  enable = %(none)s

  [[plugin]]
  name = "motion"
  enable = false

  [[plugin]]
  name = "object_detection"
  enable = false

  [[plugin]]
  name = "thumb_scale"
  enable = false
||| % {
  maxDiskUsage: maxDiskUsageGb,
  basic: if auth == 'basic' then 'true' else 'false',
  none: if auth == 'none' then 'true' else 'false',
};

function(
  name='sentryshot',
  image=defaultImage,
  auth='basic',
  maxDiskUsageGb=100,
  config=null,
  configSize='1Gi',
  storageSize='100Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '250m', memory: '256Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  assert auth == 'basic' || auth == 'none' : "sentryshot: auth must be 'basic' or 'none'";

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(2020)
  + kurly.servicePort(2020)
  // A Service named after the workload makes Kubernetes inject SENTRYSHOT_PORT
  // as a tcp:// URL; nothing here reads it, and the link variables are noise.
  + kurly.disableServiceLinks()
  // The binary needs no privileges and writes only under the two mounts, so the
  // hardened posture holds; fsGroup hands it the volumes.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/app/configs', configSize, storageClass=storageClass)
  + kurly.store('/app/storage', storageSize, storageClass=storageClass)
  + kurly.config(
    { 'sentryshot.toml': if config == null then configFile(auth, maxDiskUsageGb) else config },
    mountPath='/app/configs',
    subPath=true,
  )
  + (if env == {} then {} else kurly.env(env))
  // Probe by connection: every path answers 401 under basic auth, and a probe
  // on a 401 would kill the pod for as long as authentication is enabled.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
