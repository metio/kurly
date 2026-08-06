// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// slskd — an slskd server (a web-based client for the Soulseek file sharing
// network: search the network, queue downloads, and share your own files back).
// A plain composable kurly.http workload keeping its configuration, SQLite
// databases and downloads on a PersistentVolume. Import it and render with
// kurly.list:
//
//   local slskd = import 'github.com/metio/kurly/workloads/slskd/server.libsonnet';
//   kurly.list(slskd())
//
// Serves the web UI and API on :5030 — compose an exposure onto it.
//
// PORTS: the Soulseek peer listen port :50300 rides onto the Service beside the
// web port (the 'peer' port). Soulseek peers connect INWARD on it; without a
// route from the internet to that port the client still works but falls back to
// indirect connections, and downloads from firewalled peers fail.
//
// EGRESS: it is a client of a public network, so the pod needs egress to the
// internet. A NetworkPolicy written from the shape of the manifest blocks it and
// the app then simply logs in to nothing.
//
// HTTPS is off by default here: slskd's own listener mints a self-signed
// certificate nobody can verify, and the cluster terminates TLS at the exposure.
//
// The entrypoint drops privileges with gosu ONLY when PUID/PGID are set. Running
// as a non-root user with neither takes the branch that changes no ownership, so
// this keeps the hardened default posture — no root, no privilege escalation.
//
// Single writer: the SQLite databases live on a ReadWriteOnce volume, so one
// replica, recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='slskd',
  image=defaultImage,
  storageSize='20Gi',
  storageClass=null,
  // The Secret holding the Soulseek account (SLSKD_SLSK_USERNAME /
  // SLSKD_SLSK_PASSWORD — an account on the public network, which kurly cannot
  // mint), the web login (SLSKD_USERNAME / SLSKD_PASSWORD) and SLSKD_JWT_KEY,
  // which signs the tokens the web UI holds. slskd generates a JWT key at
  // startup when unset, so every restart logs everybody out.
  secretName='slskd',
  https=false,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(5030)
  + kurly.servicePort(5030)
  + kurly.extraPort('peer', 50300)
  + kurly.env({ [if !https then 'SLSKD_NO_HTTPS']: 'true' } + env)
  + kurly.envFromSecret(secretName)
  // Every knob this app has is an SLSKD_-prefixed environment variable, and a
  // Service named after it makes Kubernetes inject SLSKD_PORT=tcp://… into the
  // same namespace. Drop the service links rather than find out which key that
  // collides with.
  + kurly.disableServiceLinks()
  // The image creates an unprivileged account but selects none; with neither
  // PUID nor PGID set the entrypoint runs the app as whoever we are.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/app', storageSize, storageClass=storageClass)
  // The .NET host extracts its bundle here (the image pre-creates it 0777), and
  // a read-only root filesystem otherwise stops the process before it starts.
  + kurly.scratch('/.net')
  + kurly.scratch('/tmp')
  // /health is anonymous — the same endpoint the image's own healthcheck reads.
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
