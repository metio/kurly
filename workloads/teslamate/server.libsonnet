// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// teslamate — a TeslaMate server (logs a Tesla's drives, charges and state of
// charge into PostgreSQL and reports efficiency, cost and mileage from it). A
// plain composable kurly.http workload: everything it records lives in an
// EXTERNAL PostgreSQL — the cnpg-cluster workload provides one — so the pod
// itself is stateless. Import it and render with kurly.list:
//
//   local teslamate = import 'github.com/metio/kurly/workloads/teslamate/server.libsonnet';
//   kurly.list(teslamate())
//
// Serves the web app on :4000 — compose an exposure onto it.
//
// THE WEB APP HAS NO ACCOUNTS. Anyone who reaches it can read where the car has
// been and drive its sleep settings, so put an authenticating proxy in front of
// any exposure that leaves the cluster.
//
// The dashboards are a SEPARATE piece of software: TeslaMate ships Grafana
// dashboards that read the same database, and this workload is the logger only.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='teslamate',
  image=defaultImage,
  // The PostgreSQL it logs into. The non-secret coordinates are env; the password
  // lives in the Secret.
  dbHost='teslamate-db-rw',
  dbPort=5432,
  database='teslamate',
  dbUser='teslamate',
  // The Secret holding DATABASE_PASS and ENCRYPTION_KEY. ENCRYPTION_KEY encrypts
  // the stored Tesla API tokens: change it and the saved credentials can no
  // longer be read, so it belongs in the Secret from the first deploy.
  secretName='teslamate',
  // MQTT is optional and off by default. Set mqttHost to publish live car state
  // to a broker.
  mqttHost=null,
  // Drives, charges and reports are rendered in this zone.
  timezone='UTC',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.port(4000)
  + kurly.servicePort(4000)
  + kurly.env(
    {
      DATABASE_HOST: dbHost,
      DATABASE_PORT: std.toString(dbPort),
      DATABASE_NAME: database,
      DATABASE_USER: dbUser,
      TZ: timezone,
      PORT: '4000',
    }
    + (if mqttHost == null then { DISABLE_MQTT: 'true' } else { MQTT_HOST: mqttHost })
    + env
  )
  + kurly.envFromSecret(secretName)
  // The image's own USER is the NAME `nonroot`, which the kubelet cannot resolve
  // to a uid, so runAsNonRoot alone refuses the container before it starts. These
  // are that account's ids from the image.
  + kurly.runAs(10000, 10001)
  // The Erlang release is started from its own install tree: it writes the
  // generated vm.args and env.sh under /opt/app/tmp, and the elevation cache into
  // /opt/app/.srtm_cache. HOME is that same tree, so a scratch would hide the
  // application rather than give it somewhere to write.
  + kurly.writableRootFilesystem()
  // Database migrations run before the endpoint listens, so the first start is
  // slower than every later one.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  // Probed by connection: every page redirects to the sign-in flow of whatever
  // proxy fronts it, and TeslaMate answers unauthenticated requests with a
  // redirect of its own.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
