// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// matchering — a Matchering Web server (audio mastering by reference: upload a
// track and a reference you want it to sound like, and it matches the loudness,
// frequency balance and stereo width). A plain composable kurly.http workload;
// uploads and rendered results live on a PersistentVolume. Import it and render
// with kurly.list:
//
//   local matchering = import 'github.com/metio/kurly/workloads/matchering/server.libsonnet';
//   kurly.list(matchering())
//
// Serves the web app on :8360 — compose an exposure onto it.
//
// MASTERING IS CPU WORK. A single job saturates whatever it is given for the
// length of the track, so the limit here is what stops one upload starving its
// neighbours rather than a guess at what is enough.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='matchering',
  image=defaultImage,
  // Uploads and rendered results, which is what grows.
  storageSize='20Gi',
  storageClass=null,
  // The Secret holding a `secret_key` entry — Django's SECRET_KEY, which signs
  // sessions. See the comment on the mount below for why this is not optional in
  // practice.
  secretName='matchering',
  env={},
  resources={ requests: { cpu: '500m', memory: '1Gi' }, limits: { cpu: '2', memory: '4Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8360)
  + kurly.servicePort(8360)
  + (if env == {} then {} else kurly.env(env))
  // supervisord is configured to drop privileges to its own account, and refuses
  // to start when it is already unprivileged — "Can't drop privilege as nonroot
  // user" — so root here is required rather than merely the image's default. The
  // capabilities and the escalation are what the drop itself needs.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  // Django writes inside its own tree — the entrypoint generates .secret_key beside
  // the code, and `manage.py migrate` runs before anything serves.
  + kurly.writableRootFilesystem()
  + kurly.store('/app/data', storageSize, storageClass=storageClass)
  // The SECRET_KEY is read from a FILE and from nowhere else: settings.py opens
  // ./.secret_key, and the entrypoint generates one when it is absent. On an
  // ephemeral filesystem that means a new key on every restart, which does not
  // fail — it silently invalidates every session and anything else Django signed.
  //
  // Mounting one key as that single file fixes it without shadowing the install
  // tree, and the entrypoint then finds the file present and leaves it alone.
  + kurly.secretMount(secretName, '/app/.secret_key', subPath='secret_key')
  + kurly.scratch('/tmp')
  // Django migrations run before the server binds.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
