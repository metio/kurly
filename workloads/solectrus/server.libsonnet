// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// solectrus — a SOLECTRUS dashboard (a photovoltaic dashboard: what the panels
// produce, what the house consumes, what goes to and comes from the grid, and what
// that is worth). A plain composable kurly.http workload on the official image,
// backed by three external services. Import it, point it at them, and render with
// kurly.list:
//
//   local solectrus = import 'github.com/metio/kurly/workloads/solectrus/server.libsonnet';
//   kurly.list(solectrus())
//
// Serves the web app on :3000 — compose an exposure onto it.
//
// BACKENDS: this is the DASHBOARD only. The measurements it draws are written to
// InfluxDB by collectors that run beside a PV system and are not carried here, so a
// fresh instance with nothing feeding it renders empty rather than broken. It needs
// all three of an InfluxDB 2 (the measurements), a PostgreSQL (its own records; the
// database must be named solectrus_production, which config/database.yml hard-codes)
// and a Redis (cache and ActionCable). The entrypoint waits for each in turn and
// refuses to start without DB_HOST, INFLUX_HOST and REDIS_URL, so a missing one is a
// pod that never listens rather than one that answers wrongly. The database defaults
// pair with a cnpg-cluster named solectrus-db.
//
// SECRETS: kurly authors no Secret; provide one holding DB_PASSWORD, REDIS_URL,
// INFLUX_TOKEN, SECRET_KEY_BASE and ADMIN_PASSWORD, pulled in via envFrom.
// SECRET_KEY_BASE signs the session cookies, so a value that changes on every restart
// signs everybody out; ADMIN_PASSWORD is what guards the settings the dashboard can
// change; INFLUX_TOKEN only has to be able to READ the bucket, and giving it the
// admin token hands a browser-facing app write access to the measurement history.
//
// Stateless: everything is in PostgreSQL, InfluxDB and Redis, so this stage claims no
// volume and rolls.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='solectrus',
  image=defaultImage,
  replicas=1,
  // The Secret holding DB_PASSWORD, REDIS_URL, INFLUX_TOKEN, SECRET_KEY_BASE and
  // ADMIN_PASSWORD (kurly mints none), pulled into the environment via envFrom.
  secretName='solectrus',
  dbHost='solectrus-db-rw',
  dbPort=5432,
  dbUser='solectrus',
  influxHost='influxdb',
  influxPort=8086,
  influxScheme='http',
  influxOrg='solectrus',
  influxBucket='solectrus',
  // The hostname a browser reaches this instance at. Rails checks it against the
  // request's Host header, so a wrong value answers 403 to everybody.
  appHost='solectrus.example.com',
  // Rails redirects every plain request to https when this is on. Leave it off where
  // something else terminates TLS and forwards the scheme; turn it on where the pod
  // is reached directly over TLS.
  forceSsl=false,
  // The day the PV system first produced anything — every all-time figure is counted
  // from it, so the dashboard's totals are wrong until it is set.
  installationDate='2025-01-01',
  timezone='Europe/Berlin',
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(3000)
  + kurly.servicePort(3000)
  + kurly.envFromSecret(secretName)
  + kurly.env(
    {
      TZ: timezone,
      APP_HOST: appHost,
      FORCE_SSL: if forceSsl then 'true' else 'false',
      INSTALLATION_DATE: installationDate,
      DB_HOST: dbHost,
      DB_PORT: std.toString(dbPort),
      DB_USER: dbUser,
      INFLUX_HOST: influxHost,
      INFLUX_PORT: std.toString(influxPort),
      INFLUX_SCHEMA: influxScheme,
      INFLUX_ORG: influxOrg,
      INFLUX_BUCKET: influxBucket,
    }
    + env
  )
  // The image's USER is the NAME `app`, which kubelet cannot check against
  // runAsNonRoot — it refuses to start a container whose user is non-numeric — so
  // pin the uid Alpine gives the account the image creates.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // Rails writes its pid file, its bootsnap cache and its ActiveSupport caches under
  // the application tree, which is read-only here.
  + kurly.scratch('/app/tmp', '256Mi')
  + kurly.scratch('/tmp', '128Mi')
  // The entrypoint waits for Redis, InfluxDB and PostgreSQL and then runs
  // `rails db:prepare` before anything listens; a liveness probe alone would restart
  // it mid-migration, and against a dependency that is still coming up it would
  // restart it forever.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 5, failureThreshold: 60 })
  // Probed by connection: Rails checks the Host header against APP_HOST and answers
  // 403 to a probe that names the pod IP, and with forceSsl on it redirects the
  // kubelet to a port it then cannot speak TLS to.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
