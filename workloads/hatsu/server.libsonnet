// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// hatsu — a Hatsu server (a bridge that speaks ActivityPub on behalf of a static
// site: it turns the site's JSON feed into a Fediverse actor, accepts follows,
// pushes new posts to the followers and collects the replies). A plain composable
// kurly.http workload keeping its SQLite database on a PersistentVolume. Import it
// and render with kurly.list:
//
//   local hatsu = import 'github.com/metio/kurly/workloads/hatsu/server.libsonnet';
//   kurly.list(hatsu(domain='hatsu.example.com', primaryAccount='blog.example.com'))
//
// Serves the ActivityPub, Mastodon-compatible and admin API on :3939 — compose an
// exposure onto it.
//
// DOMAIN AND PRIMARYACCOUNT ARE REQUIRED, and the process REFUSES TO START without
// them: Hatsu panics on a missing HATSU_DOMAIN or HATSU_PRIMARY_ACCOUNT rather than
// picking something. Neither has a sane default — the domain is the one in every
// @handle this instance mints, and the primary account is the static site being
// bridged — so both are unset here and a pod without them crash-loops by design.
//
// IT FETCHES THE SITE ON FIRST START. Creating the primary account reads that
// site's JSON feed over the internet, and a failure there ends the process, so the
// pod needs egress and the site needs a feed Hatsu can parse before the first roll
// ever succeeds. A NetworkPolicy composed onto this workload that forgets the
// egress keeps it from starting at all, not merely from federating.
//
// The database URL carries ?mode=rwc deliberately: without it SQLite opens an
// existing file and fails on an empty volume, which is exactly the state a fresh
// deployment is in.
//
// Single writer: one SQLite database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='hatsu',
  image=defaultImage,
  storageSize='5Gi',
  storageClass=null,
  // The domain this instance answers on — it is part of every @handle it mints,
  // so it is permanent in practice.
  domain=null,
  // The static site being bridged, as a bare host. Hatsu reads its JSON feed.
  primaryAccount=null,
  // The Secret holding HATSU_ACCESS_TOKEN, which guards the admin API. Hatsu
  // serves that API only when the token is set, and creating any further account
  // goes through it — so without the Secret the instance is limited to the
  // primary account for good.
  secretName='hatsu',
  logLevel='info',
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv =
    {
      HATSU_LOG: logLevel,
      // Absolute, so the database lands on the volume whatever directory the
      // binary is invoked from; mode=rwc creates it on an empty volume.
      HATSU_DATABASE_URL: 'sqlite:///data/hatsu.sqlite3?mode=rwc',
      // The image's own default is 127.0.0.1, which no kubelet probe and no
      // Service can reach.
      HATSU_LISTEN_HOST: '0.0.0.0',
      HATSU_LISTEN_PORT: '3939',
    }
    + (if domain == null then {} else { HATSU_DOMAIN: domain })
    + (if primaryAccount == null then {} else { HATSU_PRIMARY_ACCOUNT: primaryAccount });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3939)
  + kurly.servicePort(3939)
  + kurly.env(baseEnv + env)
  + kurly.envFromSecret(secretName)
  // A single static binary that selects no account, binds an unprivileged port
  // and writes only under /data.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp')
  // The image's own healthcheck path: it answers 204 without a session and
  // without redirecting.
  + kurly.readinessProbe({ httpGet: { path: '/api/v0/generate_204', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/v0/generate_204', port: 'http' } })
  // First start runs the database migrations and fetches the primary account's
  // feed before anything listens.
  + kurly.startupProbe({ httpGet: { path: '/api/v0/generate_204', port: 'http' }, periodSeconds: 5, failureThreshold: 60 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
