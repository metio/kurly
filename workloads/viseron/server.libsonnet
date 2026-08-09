// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// viseron — a Viseron server (records network cameras and runs object detection
// over the footage, keeping only the events worth keeping). A plain composable
// kurly.http workload on the official image: its configuration, recorded segments,
// snapshots, thumbnails and event clips all live on a PersistentVolume, so it needs
// no external database. Import it and render with kurly.list:
//
//   local viseron = import 'github.com/metio/kurly/workloads/viseron/server.libsonnet';
//   kurly.list(viseron())
//
// Serves the web UI and API on :8888 — compose an exposure onto it.
//
// CAMERAS: Viseron is configured entirely from /config/config.yaml on the volume. A
// default one is written on the first start and has no cameras in it, so the first
// thing to do after the rollout is to edit it in the web UI and let it restart.
//
// FOOTAGE IS THE VOLUME: recorded video is what fills the disk here, and it fills it
// continuously — size the volume for the retention the cameras' config asks for
// rather than for the application.
//
// The s6-overlay init runs as root and drops to the `abc` account, so this runs as
// root with the capabilities that transition needs granted back BY NAME, and with a
// writable root filesystem because s6 supervises nginx, PostgreSQL, go2rtc and
// Viseron itself from the image's own tree; kurly keeps the rest of the hardening
// (seccomp, no privilege escalation, everything else dropped, resource limits). Set
// puid/pgid to own the files on the volume.
//
// Probes are CONNECTION probes: the web server answers the application's own routes
// through a single-page app whose paths move between releases, and a probe naming one
// that answers 404 would restart the pod forever.
//
// Single writer: the configuration and the footage live on a ReadWriteOnce volume, so
// one replica, recreated (never rolled) to keep two pods off the same files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='viseron',
  image=defaultImage,
  // Configuration AND the recorded footage; the footage is what grows.
  storageSize='100Gi',
  storageClass=null,
  puid=911,
  pgid=911,
  timezone='UTC',
  env={},
  resources={ requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '4Gi' } },
  labels={},
  annotations={},
)
  // Viseron writes its recordings, snapshots, thumbnails and event clips to
  // top-level directories beside its code rather than under the configuration
  // directory; surface all of them as subpaths of the same volume.
  local media = {
    deployment+: { spec+: { template+: { spec+: {
      containers: [
        container { volumeMounts+: [
          { name: 'store', mountPath: '/segments', subPath: 'segments' },
          { name: 'store', mountPath: '/snapshots', subPath: 'snapshots' },
          { name: 'store', mountPath: '/thumbnails', subPath: 'thumbnails' },
          { name: 'store', mountPath: '/event_clips', subPath: 'event_clips' },
        ] }
        for container in super.containers
      ],
    } } } },
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8888)
  + kurly.servicePort(8888)
  + kurly.env({ PUID: std.toString(puid), PGID: std.toString(pgid), TZ: timezone } + env)
  // A Service named after the workload makes Kubernetes inject VISERON_PORT as a
  // tcp:// URL, and every VISERON_* variable here is read as configuration.
  + kurly.disableServiceLinks()
  // The s6-overlay init starts as root and drops to PUID/PGID.
  + kurly.rootUser()
  // Everything is dropped and these are granted back by name — the set the
  // privilege drop and the volume ownership fixup need, and nothing else.
  + kurly.addCapabilities(['CHOWN', 'DAC_OVERRIDE', 'FOWNER', 'SETGID', 'SETUID'])
  // s6-overlay compiles its service database into the image's own tree and
  // supervises nginx, PostgreSQL, go2rtc and Viseron itself from there, so the
  // root filesystem has to be writable — an emptyDir over /run alone leaves every
  // supervised service failing to exec its own run script.
  + kurly.writableRootFilesystem()
  // ffmpeg's scratch files, bounded so a wedged remux cannot fill the node.
  + kurly.scratch('/tmp', '1Gi')
  + kurly.store('/config', storageSize, storageClass=storageClass)
  // Loading the detector models and opening every camera takes minutes on the first
  // start, which is a startup budget rather than a longer liveness delay.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 60, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + media
