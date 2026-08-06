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
  // The proxies whose forwarded headers Caddy and Laravel trust.
  trustedProxies='*',
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
    DB_CONNECTION: 'sqlite',
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
  + kurly.runAs(33, gid=33, fsGroup=33)
  + kurly.addCapabilities(['NET_BIND_SERVICE'])
  + kurly.allowPrivilegeEscalation()
  + kurly.writableRootFilesystem()
  + kurly.store('/pelican-data', storageSize, storageClass=storageClass)
  // Migrations, the Filament optimize pass and the first asset cache make the first
  // start slow — that is a startup budget, not a liveness delay.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 60 })
  + kurly.readinessProbe({ httpGet: { path: '/up', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
