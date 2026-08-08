// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// roundup-issue-tracker — a Roundup issue tracker (issues reachable over the web,
// by email and from a command line, on a schema you can change). A composable
// kurly.http workload keeping the tracker home — configuration, templates and the
// SQLite database — on a PersistentVolume. Import it and render with kurly.list:
//
//   local roundup = import 'github.com/metio/kurly/workloads/roundup-issue-tracker/server.libsonnet';
//   kurly.list(roundup())
//
// Serves on :8080, with the tracker under /<tracker>/ — compose an exposure onto
// it.
//
// FIRST RUN: the image's own start script installs a tracker by ASKING which
// template and which backend on a terminal, which no cluster provides — with
// nothing to answer it the container exits and never serves. The init container
// does the same two steps non-interactively (install the template with the web
// URL already set, then initialise the database with the administrator's
// password), so the start script finds a configured tracker and execs the server.
// It only acts on what is missing, so a tracker an operator has since edited or
// filled with issues is left alone on every restart.
//
// webUrl is the address the tracker believes it lives at. Roundup writes it into
// every link it renders and every mail it sends, so a wrong value produces a site
// that works until somebody follows a link. Only the FIRST run reads it; change it
// in config.ini on the volume afterwards.
//
// Single writer: the tracker home is one directory tree on a ReadWriteOnce volume,
// so one replica, recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

// Installs and initialises the tracker home on an empty volume. Both steps are
// the interactive ones the image's start script would otherwise run: `install`
// takes the template, the backend and initial config values as arguments, and
// `initialise` takes the administrator's password, so neither prompts.
local setupScript = |||
  set -eu
  if [ ! -f "$TRACKER_HOME/config.ini" ]; then
    echo "Installing $TEMPLATE tracker on the $BACKEND backend in $TRACKER_HOME"
    roundup-admin -i "$TRACKER_HOME" install "$TEMPLATE" "$BACKEND" "tracker_web=$WEB_URL"
  fi
  if [ ! -e "$TRACKER_HOME/db" ]; then
    echo "Initialising the tracker database"
    roundup-admin -i "$TRACKER_HOME" initialise "$ADMIN_PASSWORD"
  fi
|||;

function(
  name='roundup-issue-tracker',
  image=defaultImage,
  // The tracker's name in the URL: it is served at /<tracker>/.
  tracker='issues',
  // The schema and page set the first run installs: classic, devel, jinja2,
  // minimal or responsive.
  template='classic',
  // The hyperdb backend: anydbm, sqlite, postgres or mysql. Only the two
  // file-backed ones are self-contained — postgres and mysql need a server, and a
  // database URL in config.ini, that this workload does not provide.
  backend='sqlite',
  // What the tracker believes its own address is. Read on the first run only.
  webUrl='http://localhost:8080/issues/',
  // Holds ADMIN_PASSWORD, the password of the tracker's `admin` account. Read once,
  // when the database is initialised.
  secretName='roundup-issue-tracker',
  storageSize='5Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  // The image's CMD, stated so the tracker name is a parameter rather than a
  // default baked into the image: `<name>=<tracker home>`, relative to /usr/src/app.
  + kurly.args([tracker + '=tracker'])
  + (if env == {} then {} else kurly.env(env))
  // The image runs as its own `roundup` account (uid 1000) and everything it
  // writes is under the tracker home, so the hardened default stands. The uid is
  // pinned here for the fsGroup, without which the freshly provisioned volume
  // belongs to root and the install cannot write a single file into it.
  + kurly.runAs(1000)
  + kurly.store('/usr/src/app/tracker', storageSize, storageClass=storageClass)
  + kurly.initContainer({
    name: 'install',
    image: image,
    command: ['/bin/sh', '-c', setupScript],
    workingDir: '/usr/src/app',
    env: [
      { name: 'TRACKER_HOME', value: '/usr/src/app/tracker' },
      { name: 'TEMPLATE', value: template },
      { name: 'BACKEND', value: backend },
      { name: 'WEB_URL', value: webUrl },
      { name: 'ADMIN_PASSWORD', valueFrom: { secretKeyRef: { name: secretName, key: 'ADMIN_PASSWORD' } } },
    ],
    volumeMounts: [{ name: 'store', mountPath: '/usr/src/app/tracker' }],
  })
  // Probe by connection: the server answers / with a tracker index and each
  // tracker below its own path, and both redirect depending on how the tracker is
  // configured — a probe that follows one is a probe that can start failing on a
  // configuration change nobody connected to the pod dying.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 30 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
