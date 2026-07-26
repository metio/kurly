// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// frigate — a self-hosted NVR with real-time object detection. It keeps its
// configuration and SQLite database on a PersistentVolume at /config and the
// recordings and clips on a second volume at /media, decodes frames through a
// large shared-memory scratch at /dev/shm, and stages recording segments in a
// tmpfs-like scratch at /tmp/cache. Compose an exposure onto the authenticated
// UI on :8971:
//
//   local frigate = import 'github.com/metio/kurly/workloads/frigate/server.libsonnet';
//   kurly.list(frigate())
//
// The shipped config.yml is a minimal starting point (MQTT off, a CPU detector,
// no cameras) — replace it with your own cameras and detectors. It mounts
// read-only over the /config volume, so Frigate's built-in config editor is
// disabled; to edit config in the UI instead, drop the `config` parameter and
// seed config.yml onto the volume yourself.
//
// Hardware detectors (a Coral TPU, a GPU) need device access the restricted
// posture does not grant. This recipe runs CPU detection out of the box; for an
// accelerator, add the device mounts and the privileges your cluster requires
// with the raw `+` escape hatch.
//
// Two ReadWriteOnce volumes, so one replica, recreated.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

// A minimal, valid Frigate config: no broker, a CPU detector, no cameras yet.
local defaultConfig = |||
  mqtt:
    enabled: false
  detectors:
    cpu:
      type: cpu
  # Add your cameras here — see https://docs.frigate.video/configuration/
  cameras: {}
|||;

function(
  name='frigate',
  image=defaultImage,
  config=defaultConfig,
  storageSize='1Gi',
  mediaSize='100Gi',
  storageClass=null,
  shmSize='256Mi',
  cacheSize='1Gi',
  secretName='frigate-secrets',
  env={},
  resources={ requests: { cpu: '500m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  // The authenticated UI/API is the port to expose; the plain UI/API stays
  // in-cluster on 5000, and the restreams ride their own ports.
  + kurly.port(8971)
  + kurly.servicePort(8971)
  + kurly.extraPort('http-plain', 5000)
  + kurly.extraPort('rtsp', 8554)
  + kurly.extraPort('webrtc-tcp', 8555)
  + kurly.extraPort('webrtc-udp', 8555, protocol='UDP')
  // Frigate's s6 supervisor and ffmpeg run as root and write across the root
  // filesystem, so run as root with a writable root filesystem.
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/config', storageSize, storageClass=storageClass)
  + kurly.store('/media', mediaSize, storageClass=storageClass)
  // config.yml rides read-only over the /config volume as a single file, leaving
  // the SQLite database and model cache on the volume beside it writable.
  + kurly.config({ 'config.yml': config }, mountPath='/config', subPath=true)
  // Decoded frames land in /dev/shm; recording segments stage in /tmp/cache.
  // Both are emptyDir scratch — size /dev/shm for the camera count, or the
  // decoder aborts with a bus error.
  + kurly.scratch('/dev/shm', shmSize)
  + kurly.scratch('/tmp/cache', cacheSize)
  // FRIGATE_RTSP_PASSWORD (and any other secret) comes from an operator-supplied
  // Secret; kurly mints none.
  + kurly.envFromSecret(secretName)
  + kurly.env(env)
  + kurly.readinessProbe({ httpGet: { path: '/api/version', port: 'http-plain' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/version', port: 'http-plain' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
