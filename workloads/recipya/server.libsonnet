// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// recipya — a Recipya server (a recipe manager: import recipes from a website or a
// photo, plan meals for the week and turn the plan into a shopping list). A plain
// composable kurly.http workload keeping its SQLite databases, images and videos on
// a PersistentVolume. Import it and render with kurly.list:
//
//   local recipya = import 'github.com/metio/kurly/workloads/recipya/server.libsonnet';
//   kurly.list(recipya())
//
// Serves the web app on :8078 — compose an exposure onto it. The port is not the
// image's EXPOSE (which still says 8080); Recipya listens on whatever
// RECIPYA_SERVER_PORT names and has no default of its own, so the env and the
// container port are set from one parameter here.
//
// FIRST BOOT REACHES THE INTERNET, AND EXITS IF IT CANNOT. Recipya downloads a
// 62 MB nutrition database (FDC) from githubusercontent into its data directory the
// first time it starts, and calls os.Exit(1) when that download fails — so a
// NetworkPolicy composed onto this workload must allow egress to the internet, at
// least until the file is on the volume. That download is also why the startup
// probe is generous: the pod is not listening while it runs.
//
// THE EMPTY DIRECTORY AT /.dockerenv IS LOAD-BEARING. Recipya decides whether to
// read its configuration from the environment or to write a config.json by asking
// whether /.dockerenv exists. Under Kubernetes it does not, so the app takes the
// interactive path, gets EOF on every prompt, accepts the defaults — and one of
// those defaults binds a RANDOM ephemeral port, which it then persists. Mounting an
// empty directory at that path makes the stat succeed and keeps the app on the
// documented environment-variable configuration.
//
// Single writer: SQLite on a ReadWriteOnce volume, so one replica, recreated
// (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='recipya',
  image=defaultImage,
  port=8078,
  storageSize='10Gi',
  storageClass=null,
  // The URL the browser reaches this instance at. Recipya builds the links it
  // shares and mails from it, so a wrong value renders a UI whose links go
  // somewhere else. Absent leaves it unset rather than baking in a default that is
  // wrong everywhere it is really deployed.
  baseUrl=null,
  // Refuse new registrations once the accounts that should exist do.
  noSignups=false,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(port)
  + kurly.servicePort(port)
  + kurly.env(
    {
      // Recipya has no built-in port and exits when this is unset.
      RECIPYA_SERVER_PORT: std.toString(port),
      RECIPYA_SERVER_IS_PROD: 'true',
      RECIPYA_SERVER_NO_SIGNUPS: if noSignups then 'true' else 'false',
      // os.UserConfigDir decides where the databases, images and logs live; pinning
      // it puts them on the volume regardless of what HOME happens to be.
      XDG_CONFIG_HOME: '/data',
    }
    + (if baseUrl == null then {} else { RECIPYA_SERVER_URL: baseUrl })
    + env
  )
  // The image declares root:root but writes only inside its data directory, which
  // fsGroup hands over — so it runs unprivileged with the hardened defaults intact.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp')
  // Present, not used: see the note above about /.dockerenv.
  + kurly.scratch('/.dockerenv', '1Mi')
  // The nutrition database download runs before the server listens, so a liveness
  // probe alone would restart the pod in the middle of it, forever.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 60 })
  // GET / answers only when signed in and redirects otherwise; probe the
  // connection instead of picking a path whose status depends on a session.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
