// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// pelican-panel — a Pelican Panel server (a web control panel for running and
// managing game servers). A plain composable kurly.http workload on the official
// image: it keeps its SQLite database, its .env, uploads and plugins under
// /pelican-data on a PersistentVolume, so it needs no external database. Import it
// and render with kurly.list:
//
//   local pelican = import 'github.com/metio/kurly/workloads/pelican-panel/server.libsonnet';
//   kurly.list(pelican(appUrl='https://panel.example.com'))
//
// Serves the web UI and API on :80 — compose an exposure onto it.
//
// BEHIND A PROXY: the entrypoint decides what Caddy listens on. With
// behindProxy=true (the default) it listens on plain :80 with automatic HTTPS off
// and takes the public origin from APP_URL — which is what an Ingress or HTTPRoute
// terminating TLS in front of it wants. Turning it off makes Caddy bind the APP_URL
// host itself and demand a Let's Encrypt address for an https:// URL.
//
// APP_KEY: the entrypoint mints one into /pelican-data/.env on first start when the
// environment carries none, so a Secret is optional; pass one through secretName to
// pin the key across a rebuilt volume. kurly authors no Secret.
//
// The image runs as its own www-data user and Caddy binds the privileged :80 through
// a file capability, so this grants NET_BIND_SERVICE back on top of the dropped-ALL
// default and allows privilege escalation — without it no_new_privs discards the
// file capability and nothing ever listens. The root filesystem is writable because
// the Laravel tree is optimized, cached and logged into in place.
//
// Single writer: the SQLite database and the uploads live on a ReadWriteOnce volume,
// so one replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='pelican-panel',
  image=defaultImage,
  storageSize='5Gi',
  storageClass=null,
  // The public URL the panel builds links and assets against.
  appUrl=null,
  // Let the proxy in front terminate TLS and keep Caddy on plain :80.
  behindProxy=true,
  // The proxies whose forwarded headers Caddy and Laravel trust, as CIDR ranges.
  // NOT '*': Caddy's trusted_proxies parses each entry as an address or prefix and
  // refuses to start on a glob — "invalid IP address: '*': ParseAddr("*")" — which
  // stops the whole server over a value that reads like the obvious way to say
  // "any". The default trusts everything, which is what a workload behind an
  // in-cluster ingress needs; narrow it to the proxy's own range where the pod is
  // reachable by anything else.
  trustedProxies='0.0.0.0/0 ::/0',
  // The database. SQLite on the volume needs nothing else and is the default;
  // point dbConnection at 'pgsql' or 'mysql' and supply the DB_* variables through
  // env or the Secret to move it to an external server, which also skips the
  // init container that creates the SQLite file.
  dbConnection='sqlite',
  databasePath='/pelican-data/database/database.sqlite',
  // An optional Secret holding APP_KEY and any database credentials, via envFrom.
  secretName=null,
  env={},
  resources={ requests: { cpu: '200m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local proxyEnv = if behindProxy then { BEHIND_PROXY: 'true' } else {};
  local urlEnv = if appUrl == null then {} else { APP_URL: appUrl };
  local baseEnv = {
    APP_ENV: 'production',
    APP_INSTALLED: 'false',
    DB_CONNECTION: dbConnection,
    // ON THE VOLUME, AND NAMED. Laravel resolves an unset DB_DATABASE to its own
    // default inside the install tree, so the database was neither on the volume
    // nor present: every request ended "Database file at path
    // [/var/www/html/database/database.sqlite] does not exist" and the readiness
    // probe read 500, while the container itself looked healthy. The entrypoint
    // creates this directory on the volume but never the file.
    DB_DATABASE: databasePath,
    CACHE_STORE: 'file',
    QUEUE_CONNECTION: 'database',
    SESSION_DRIVER: 'file',
    TRUSTED_PROXIES: trustedProxies,
  } + proxyEnv + urlEnv;

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + (if secretName == null then {} else kurly.envFromSecret(secretName))
  + kurly.env(baseEnv + env)
  // Everything is dropped and this one is granted back by name: Caddy carries
  // cap_net_bind_service as a file capability, which no_new_privs would discard.
  // The image declares its user by NAME (www-data), and runAsNonRoot cannot
  // verify a name — the kubelet refuses the container with "image has
  // non-numeric user", before it is ever started, which surfaces as a
  // CreateContainerConfigError rather than anything about the application. The
  // numeric equivalent is stated here so the hardened default still applies.
  //
  // THE NUMBER IS ALPINE'S 82, NOT DEBIAN'S 33. This image is Alpine-based, where
  // www-data is 82; running it as 33 leaves the process a stranger to its own
  // tree, which is mode drwxrwx--- and grants nothing to others. The entrypoint's
  // `mkdir -p … /var/www/html/storage/logs/supervisord` then fails — silently,
  // because that line redirects its errors away — and supervisord dies on "The
  // directory named as part of the path …/supervisord.log does not exist", which
  // names a missing directory rather than the identity that could not create it.
  + kurly.runAs(82, gid=82, fsGroup=82)
  + kurly.addCapabilities(['NET_BIND_SERVICE'])
  + kurly.allowPrivilegeEscalation()
  + kurly.writableRootFilesystem()
  + kurly.store('/pelican-data', storageSize, storageClass=storageClass)
  // THE DATABASE FILE HAS TO EXIST BEFORE LARAVEL OPENS IT. Nothing else creates
  // it: the image's entrypoint makes /pelican-data/database and stops there, and
  // Laravel refuses a missing SQLite file rather than creating one — every request
  // then ends "Database file at path [...] does not exist" and the readiness probe
  // reads 500 while the container itself looks healthy. Creating it is idempotent,
  // so this runs before every start and brings a fresh volume up with no manual
  // step; an existing database is left exactly as it is.
  + (if dbConnection != 'sqlite' then {} else kurly.initContainer({
       name: 'create-database',
       image: image,
       command: ['/bin/sh', '-c', 'mkdir -p "$(dirname "$DB_DATABASE")" && touch "$DB_DATABASE"'],
       env: [{ name: 'DB_DATABASE', value: databasePath }],
       volumeMounts: [{ name: 'store', mountPath: '/pelican-data' }],
     }))
  // Migrations, the Filament optimize pass and the first asset cache make the first
  // start slow — that is a startup budget, not a liveness delay.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 60 })
  // A CONNECTION CHECK, NOT /up. Laravel's health endpoint touches the database,
  // and a fresh panel has no schema: the entrypoint runs its migrations only when
  // APP_INSTALLED is true, because the first run is meant to be completed in the
  // browser installer. Probing /up therefore answers 500 until a human finishes
  // the install, so a correctly deployed panel would never become Ready and the
  // rollout would fail waiting for the one step it cannot take by itself.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
