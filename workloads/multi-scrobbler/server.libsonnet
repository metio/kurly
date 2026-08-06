// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// multi-scrobbler — a multi-scrobbler server (it watches what you are listening to
// across many sources — Spotify, Plex, Jellyfin, YouTube Music, a desktop player —
// and forwards each play to the scrobbling services that keep your history, such as
// Last.fm, ListenBrainz or Maloja). A plain composable kurly.http workload on the
// upstream image; its configuration, credentials and play database live on a
// PersistentVolume at /config. Import it and render with kurly.list:
//
//   local ms = import 'github.com/metio/kurly/workloads/multi-scrobbler/server.libsonnet';
//   kurly.list(ms())
//
// Serves the dashboard, the OAuth callbacks and the webhook endpoints on :9078 —
// compose an exposure onto it.
//
// BASE_URL IS THE ONE VALUE ONLY YOU KNOW: the sources that authenticate by OAuth
// build their redirect URI from it, so a wrong or missing one sends the browser back
// to a host that is not this instance and the authorisation never completes. Set
// baseUrl to the public URL your exposure serves; it is null by default because a
// placeholder would be wrong everywhere it is really deployed.
//
// LINUXSERVER BASE IMAGE: the s6-overlay init runs as root and drops to the
// PUID/PGID user, so this runs as root and is granted back only the capabilities
// that dropping privileges needs — kurly keeps the rest of the hardening (seccomp,
// no privilege escalation, a read-only root filesystem, resource limits). Set
// puid/pgid to own the files on the volume.
//
// Single writer: the configuration and the play database live on a ReadWriteOnce
// volume, so one replica, recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='multi-scrobbler',
  image=defaultImage,
  storageSize='2Gi',
  storageClass=null,
  // The public URL this instance is reached at. OAuth redirect URIs are built from
  // it, so it has to be the address the browser actually returns to.
  baseUrl=null,
  puid=1000,
  pgid=1000,
  timezone='UTC',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(9078)
  + kurly.servicePort(9078)
  + kurly.env(
    {
      PUID: std.toString(puid),
      PGID: std.toString(pgid),
      TZ: timezone,
    }
    + (if baseUrl == null then {} else { BASE_URL: baseUrl })
    + env
  )
  // A Service named after this workload makes Kubernetes inject MULTI_SCROBBLER_PORT
  // as a tcp:// URL, and the application reads PORT-shaped variables as its listen
  // port.
  + kurly.disableServiceLinks()
  // The s6-overlay init needs root before it drops to PUID/PGID.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  // Everything is dropped and these are granted back by name — the smallest set the
  // init needs to change ownership of the volume and become the unprivileged user.
  + kurly.addCapabilities(['CHOWN', 'DAC_OVERRIDE', 'FOWNER', 'SETGID', 'SETUID'])
  // s6 builds its service tree under /run, and node writes its temporary files.
  + kurly.scratch('/run')
  + kurly.scratch('/tmp')
  + kurly.store('/config', storageSize, storageClass=storageClass)
  // Probe by connection: the dashboard's own health endpoint reports the state of
  // the CONFIGURED sources, so a fresh instance with nothing configured yet — or one
  // whose Last.fm token expired — answers unhealthy and would be killed forever.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
