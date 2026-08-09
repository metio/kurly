// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// lyrion-music-server — a Lyrion Music Server (the music server formerly known as
// Logitech Media Server / slimserver: it indexes a music library and streams it to
// Squeezebox hardware, softsqueeze players and mobile clients). A plain composable
// kurly.http workload on the official image: its preferences, cache and scanned
// database live on a PersistentVolume, so it needs no external database. Import it
// and render with kurly.list:
//
//   local lyrion = import 'github.com/metio/kurly/workloads/lyrion-music-server/server.libsonnet';
//   kurly.list(lyrion())
//
// Serves the web UI and JSON-RPC API on :9000 — compose an exposure onto it. Put your
// music under /music on the volume; playlists are written under /playlist.
//
// PLAYERS: hardware and software players speak slimproto on :3483 (TCP and UDP, the
// discovery half) and the telnet CLI listens on :9090; both are published on the
// Service beside the web port. Route them (a NodePort or a dedicated LoadBalancer) so
// players on the LAN can reach the server — the web UI works without them.
//
// The entrypoint runs as root to renumber its own user to PUID/PGID, chown /config and
// /playlist, and then drop to that user with su — so this relaxes kurly's non-root,
// no-privilege-escalation and read-only-rootfs defaults (usermod rewrites /etc/passwd)
// while keeping the rest of the hardening. Set puid/pgid to own the mounted files.
//
// Single writer: preferences, cache and the scanned database live on a ReadWriteOnce
// volume, so one replica, recreated (never rolled) to keep two servers off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='lyrion-music-server',
  image=defaultImage,
  storageSize='50Gi',
  storageClass=null,
  puid=1000,
  pgid=1000,
  timezone='UTC',
  env={},
  // An idle server sits around 150Mi; the headroom in the limit is for the Perl
  // scanner, which is the memory-hungry half and only runs while indexing.
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  // The music library and the playlist tree live beside the server's own data on the
  // same volume; music is mounted read-only because the server only ever reads it.
  local library = {
    deployment+: { spec+: { template+: { spec+: {
      containers: [
        container { volumeMounts+: [
          { name: 'store', mountPath: '/music', subPath: 'music', readOnly: true },
          { name: 'store', mountPath: '/playlist', subPath: 'playlist' },
        ] }
        for container in super.containers
      ],
    } } } },
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(9000)
  + kurly.servicePort(9000)
  + kurly.extraPort('slimproto', 3483)
  + kurly.extraPort('slimproto-udp', 3483, protocol='UDP')
  + kurly.extraPort('cli', 9090)
  + kurly.env({ PUID: std.toString(puid), PGID: std.toString(pgid), TZ: timezone, HTTP_PORT: '9000' } + env)
  + kurly.rootUser()
  // usermod/groupmod rewrite /etc/passwd and /etc/group before the server starts, and
  // su needs SETUID/SETGID to hand the process to the unprivileged user.
  + kurly.writableRootFilesystem()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  + kurly.store('/config', storageSize, storageClass=storageClass)
  // The Service is named after the workload, so Kubernetes would inject
  // LYRION_MUSIC_SERVER_PORT=tcp://… into the pod; nothing here reads it, but the
  // links are noise a music server has no use for.
  + kurly.disableServiceLinks()
  // The server binds :9000 before it can answer the setup wizard, and the first boot
  // creates its preferences and cache trees on the fresh volume — probe by connection
  // so a redirecting or still-initialising UI never kills the pod.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 60 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + library
