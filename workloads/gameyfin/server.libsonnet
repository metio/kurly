// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// gameyfin — a Gameyfin server (a game library manager: it scans directories of
// games, enriches them with metadata and cover art, and serves the result as a
// browsable web library your users can download from). A plain composable
// kurly.http workload keeping its H2 database and stored content on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local gameyfin = import 'github.com/metio/kurly/workloads/gameyfin/server.libsonnet';
//   kurly.list(gameyfin())
//
// It refuses to start without APP_KEY — the AES key it encrypts stored
// credentials with — and generates none itself, so the Secret named by
// secretName is a hard prerequisite, not an option.
//
// Serves the web app and API on :8080 — compose an exposure onto it. The
// management endpoints Spring Boot publishes (health, metrics, prometheus) live
// on :8081 and are deliberately NOT in the Service, because a restart endpoint
// that needs no authentication rides along with them. The probes do not ask
// /actuator/health either: it reports DOWN while the library is unconfigured,
// which is the normal state of a fresh install.
//
// The games themselves are NOT on this volume. Gameyfin scans library
// directories an operator configures at runtime, so mount them where they
// actually are (an NFS export, a ReadOnlyMany claim) with a store or a scratch of their own.
//
// The entrypoint runs as root, aligns the gameyfin account to PUID/PGID, hands
// /opt/gameyfin to it and su-execs the JVM — so this runs as root with a
// writable root filesystem and the named capabilities that sequence needs;
// everything else stays dropped and the application itself never runs as root.
//
// Single writer: one H2 database on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='gameyfin',
  image=defaultImage,
  storageSize='10Gi',
  storageClass=null,
  puid=1000,
  pgid=1000,
  // The Secret holding APP_KEY — base64 of 16, 24 or 32 random bytes, the AES key
  // Gameyfin encrypts stored credentials with. It refuses to start without one
  // and generates nothing itself, so a consumer must supply it; rotating it makes
  // everything already encrypted unreadable.
  secretName='gameyfin',
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '1536Mi' } },
  labels={},
  annotations={},
)
  // Gameyfin keeps its database, its stored content and its logs in separate
  // directories beside the jar; surface the database and the logs as subpaths of
  // the same volume as the content tree.
  local extraDirs = {
    deployment+: { spec+: { template+: { spec+: {
      containers: [
        container { volumeMounts+: [
          { name: 'store', mountPath: '/opt/gameyfin/db', subPath: 'db' },
          { name: 'store', mountPath: '/opt/gameyfin/logs', subPath: 'logs' },
        ] }
        for container in super.containers
      ],
    } } } },
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.env({ PUID: std.toString(puid), PGID: std.toString(pgid) } + env)
  + kurly.envFromSecret(secretName)
  + kurly.rootUser()
  // The entrypoint rewrites the account, chowns the install tree and drops to it.
  + kurly.writableRootFilesystem()
  // Everything is dropped and these are granted back by name — the smallest set
  // the chown-then-su-exec entrypoint needs.
  + kurly.addCapabilities(['CHOWN', 'DAC_OVERRIDE', 'FOWNER', 'SETGID', 'SETUID'])
  + kurly.store('/opt/gameyfin/data', storageSize, storageClass=storageClass)
  // A JVM plus Vaadin plus the Flyway migrations against a fresh H2 database is a
  // slow first start, and nothing listens until it is done.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 45 })
  // Connection probes: the root path is the Vaadin application shell, which
  // answers a redirect or an error page depending on how far the setup has got,
  // and the actuator health endpoint reports DOWN — 500 — while the library is
  // still unconfigured, which is the normal state of a fresh install.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + extraDirs
