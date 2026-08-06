// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// tiny-tiny-rss — a Tiny Tiny RSS server (a web-based news feed reader and aggregator
// for RSS and Atom). The official image is PHP-FPM ALONE: it listens on :9000 and speaks
// FastCGI, so it serves nothing a browser can talk to. Upstream pairs it with their own
// nginx image and a feed-fetching daemon, and this workload runs all THREE processes in
// one pod — the FPM app as the workload's container, nginx and the updater as SIDECARS —
// over a shared working-copy volume, because that is the arrangement the software has.
// Import it, point it at a PostgreSQL, and render with kurly.list:
//
//   local ttrss = import 'github.com/metio/kurly/workloads/tiny-tiny-rss/server.libsonnet';
//   kurly.list(ttrss(selfUrl='https://rss.example.com/tt-rss'))
//
// The nginx sidecar serves the app on :80 UNDER /tt-rss — compose an exposure onto it.
// The path is where the app container installs its working copy ($APP_INSTALL_BASE_DIR/tt-rss),
// so it is the app's own layout rather than a choice made here.
//
// SELF URL: Tiny Tiny RSS refuses to work until TTRSS_SELF_URL_PATH is the URL a browser
// actually reaches it at, including the /tt-rss suffix. There is no default that is right
// anywhere, so `selfUrl` is a parameter and unset renders no variable at all.
//
// DATABASE & SECRETS: the app reads its PostgreSQL coordinates from TTRSS_DB_* and the
// password from TTRSS_DB_PASS. kurly authors no Secret; provide one holding TTRSS_DB_PASS,
// read via envFrom by every container that talks to the database. The non-secret
// coordinates default to a cnpg-cluster named tiny-tiny-rss-db. The app creates the
// pg_trgm extension on startup, so its database user needs to be allowed to.
//
// The startup script runs as root: it creates the `app` user, chowns the working copy,
// rsyncs the sources onto the volume, and drops to that user with sudo — so this relaxes
// kurly's non-root, no-privilege-escalation and read-only-rootfs defaults. The sidecars
// inherit that posture rather than restating one.
//
// Plugin updates are OFF by default (TTRSS_NO_STARTUP_PLUGIN_UPDATES): the startup script
// otherwise `git pull`s every local plugin from the internet before it listens, which a
// cluster with no egress waits out on every restart.
//
// Single writer: the working copy (sources, cache, uploads) lives on a ReadWriteOnce
// volume shared by all three containers, so one replica, recreated (never rolled) to keep
// two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='tiny-tiny-rss',
  image=defaultImage,
  // Upstream's nginx image, built from the same repository and release as the app.
  webImage='ghcr.io/tt-rss/tt-rss-web-nginx:latest@sha256:89a73f5fd90eeb6adb3f411fe1ae733da1417f63617ceb1f8ff3d0581e0e5aa6',
  storageSize='5Gi',
  storageClass=null,
  dbHost='tiny-tiny-rss-db-rw',
  dbPort=5432,
  database='tinytinyrss',
  dbUser='tinytinyrss',
  // The URL a browser reaches this at, including the /tt-rss suffix (required by the app).
  selfUrl=null,
  // The Secret holding TTRSS_DB_PASS (kurly mints none), via envFrom.
  secretName='tiny-tiny-rss',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local appEnv = {
    TTRSS_DB_HOST: dbHost,
    TTRSS_DB_PORT: std.toString(dbPort),
    TTRSS_DB_NAME: database,
    TTRSS_DB_USER: dbUser,
    TTRSS_NO_STARTUP_PLUGIN_UPDATES: '1',
  } + (if selfUrl == null then {} else { TTRSS_SELF_URL_PATH: selfUrl }) + env;

  // The updater is the same image and the same configuration as the app, so it is
  // built from the same object rather than a second copy of it. A consumer composing
  // kurly.env() on top reaches the app container only — pass such settings through
  // this stage's `env` parameter so the updater sees them too.
  local appEnvList = [{ name: key, value: appEnv[key] } for key in std.objectFields(appEnv)];

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  // The workload's own container speaks FastCGI, not HTTP: it carries no `http` port,
  // and the Service's targetPort resolves by name onto the nginx sidecar instead.
  + kurly.port(null)
  + kurly.extraPort('fpm', 9000, expose=false)
  + kurly.servicePort(80)
  + kurly.envFromSecret(secretName)
  + kurly.env(appEnv)
  // Everything in startup.sh before the exec runs as root — adduser, chown, sudo —
  // and sudo is setuid, so it needs privilege escalation and the capabilities back.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  // The startup script rewrites /etc/php85 and writes its error-log FIFO under /tmp.
  + kurly.writableRootFilesystem()
  + kurly.store('/var/www/html', storageSize, storageClass=storageClass)
  // nginx serves the working copy the app container installs and proxies .php to it on
  // localhost:9000. RESOLVER is only there because the template names it; the FastCGI
  // pass is a literal address, so nothing is ever resolved through it.
  + kurly.sidecar({
    name: 'web',
    image: webImage,
    ports: [{ containerPort: 80, name: 'http', protocol: 'TCP' }],
    env: [
      { name: 'APP_UPSTREAM', value: '127.0.0.1' },
      { name: 'APP_FASTCGI_PASS', value: '127.0.0.1:9000' },
      { name: 'RESOLVER', value: '127.0.0.1' },
      { name: 'APP_WEB_ROOT', value: '/var/www/html' },
      { name: 'APP_BASE', value: '/tt-rss' },
    ],
    volumeMounts: [{ name: 'store', mountPath: '/var/www/html', readOnly: true }],
    readinessProbe: { tcpSocket: { port: 'http' } },
    livenessProbe: { tcpSocket: { port: 'http' } },
    resources: { requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  })
  // Feeds are fetched by a daemon, not by the web app: without it nothing ever updates.
  // It waits for the app container to finish installing the working copy, then runs.
  + kurly.sidecar({
    name: 'updater',
    image: image,
    command: ['/bin/sh', '-c', '${SCRIPT_ROOT}/updater.sh'],
    env: appEnvList,
    envFrom: [{ secretRef: { name: secretName } }],
    volumeMounts: [{ name: 'store', mountPath: '/var/www/html' }],
    resources: { requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  })
  // The Service is named after the app, so the Service-link environment would define
  // TT_RSS_PORT as a tcp:// URL — the startup script unsets HTTP_PORT/HTTP_HOST for
  // exactly this reason, and none of the three containers wants the rest of it.
  + kurly.disableServiceLinks()
  // The first start rsyncs the sources onto the volume and migrates the schema before
  // FPM listens, and it waits for the database to accept connections first.
  + kurly.startupProbe({ tcpSocket: { port: 9000 }, periodSeconds: 10, failureThreshold: 60 })
  + kurly.readinessProbe({ tcpSocket: { port: 9000 } })
  + kurly.livenessProbe({ tcpSocket: { port: 9000 } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
