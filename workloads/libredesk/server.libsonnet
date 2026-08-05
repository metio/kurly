// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// libredesk — a Libredesk server (a self-hosted customer support desk: shared
// inboxes, conversations, assignment rules, canned responses and SLAs, in one
// binary). A composable kurly.http workload backed by an EXTERNAL PostgreSQL — the
// cnpg-cluster workload provides one. Import it and render with kurly.list:
//
//   local libredesk = import 'github.com/metio/kurly/workloads/libredesk/server.libsonnet';
//   kurly.list(libredesk(appUrl='https://support.example.com'))
//
// Serves the agent UI and API on :9000 — compose an exposure onto it.
//
// THE DATABASE IS NOT OPTIONAL and there is no embedded fallback: everything —
// conversations, users, settings — lives in PostgreSQL, so the volume this
// workload does not have is the point. It claims no PersistentVolume at all.
//
// The schema is installed by a one-off `--install` run rather than on boot, which
// is why an init container does it here: an idempotent install is safe to repeat,
// and doing it before the server starts avoids a first request against a database
// with no tables.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='libredesk',
  image=defaultImage,
  // The PostgreSQL it connects to. The non-secret coordinates are env; the password
  // lives in the Secret.
  dbHost='libredesk-db-rw',
  dbPort=5432,
  database='libredesk',
  dbUser='libredesk',
  // The public URL the agent UI and its links are built against.
  appUrl=null,
  // The Secret holding LIBREDESK_DB__PASSWORD and the application's own
  // signing keys. kurly mints none.
  secretName='libredesk',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  // The names follow the shipped config.toml's own sections, and the database one
  // is NOT under [app]: it is a top-level [db] table, so these are LIBREDESK_DB__*
  // rather than LIBREDESK_APP__DB__*. Getting that wrong does not raise anything —
  // the unmatched variables are ignored and libredesk quietly uses the file's
  // defaults, so it tries to reach a PostgreSQL called `db` and fails a DNS lookup
  // for a host nobody configured.
  local baseEnv = {
    LIBREDESK_DB__HOST: dbHost,
    LIBREDESK_DB__PORT: std.toString(dbPort),
    LIBREDESK_DB__DATABASE: database,
    LIBREDESK_DB__USER: dbUser,
    LIBREDESK_APP__SERVER__ADDRESS: '0.0.0.0:9000',
  } + (if appUrl == null then {} else { LIBREDESK_APP__ROOT_URL: appUrl });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.port(9000)
  + kurly.servicePort(9000)
  + kurly.env(baseEnv + env)
  + kurly.envFromSecret(secretName)
  // A single static binary that writes nothing: no volume, nothing relaxed.
  + kurly.runAs(1000, gid=1000)
  + kurly.scratch('/tmp')
  // Two init steps, because --install alone is not enough and the gap is silent
  // until the server refuses to start. `--install --idempotent-install` lays down
  // the schema at v0.0.0 and skips if one is already there; the server then
  // announces "there are 16 pending database upgrade(s) ... run libredesk
  // --upgrade" and exits. So the upgrade runs here too, before anything serves.
  //
  // Both are idempotent, which is what makes them safe to run on every start
  // rather than as a one-off somebody has to remember at the right moment.
  + kurly.initContainer({
    name: 'install',
    image: image,
    command: ['./libredesk', '--install', '--idempotent-install', '--yes'],
    env: [{ name: k, value: baseEnv[k] } for k in std.objectFields(baseEnv)],
    envFrom: [{ secretRef: { name: secretName } }],
  })
  + kurly.initContainer({
    name: 'upgrade',
    image: image,
    command: ['./libredesk', '--upgrade', '--yes'],
    env: [{ name: k, value: baseEnv[k] } for k in std.objectFields(baseEnv)],
    envFrom: [{ secretRef: { name: secretName } }],
  })
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
