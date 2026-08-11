// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// postal — the Postal web server (the interface and HTTP API of a full outgoing
// mail platform: applications hand it messages, it delivers them and records what
// happened to each one). A composable kurly.http workload on the official image,
// backed by an EXTERNAL MySQL/MariaDB, with no volume of its own — everything
// Postal keeps is in the database. Import it and render with kurly.list:
//
//   local postal = import 'github.com/metio/kurly/workloads/postal/server.libsonnet';
//   kurly.list(postal())
//
// Serves the interface and API on :5000 — compose an exposure onto it.
//
// A working install is THREE stages: this one, `worker` (which actually delivers
// the queued mail) and `smtp` (which accepts it over SMTP). The web server alone
// takes messages through the HTTP API and never sends them.
//
// CONFIGURATION is entirely environment, no postal.yml: Postal v3 reads every
// config key from an env var named after it (main_db.host -> MAIN_DB_HOST), and
// the image's config file path simply stays empty. TWO databases: the main one
// holds the organisations, servers and routes, while the message database holds
// one schema PER MAIL SERVER, created by Postal at runtime — so the account named
// by messageDbUser needs CREATE DATABASE on the prefix, which the main login does
// not need.
//
// Stateless: the web server owns nothing on disk, so scale it with kurly.replicas.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='postal',
  image=defaultImage,
  // The hostnames Postal builds its own URLs and its SMTP banner from. The web
  // one ends up in every link it mails out, so it is the address a browser really
  // reaches this instance on.
  webHostname='postal.example.com',
  webProtocol='https',
  smtpHostname='postal.example.com',
  // The MySQL/MariaDB it connects to. The non-secret coordinates are env; the
  // passwords live in the Secret.
  dbHost='postal-db',
  dbPort=3306,
  database='postal',
  dbUser='postal',
  messageDbUser='postal',
  messageDbPrefix='postal',
  // The Secret holding MAIN_DB_PASSWORD, MESSAGE_DB_PASSWORD, RAILS_SECRET_KEY and
  // SIGNING_KEY. kurly mints none of them. It is read twice: as environment, and
  // as files under /secrets, which is where SIGNING_KEY — an RSA private key, not
  // a password — is read from.
  secretName='postal',
  replicas=1,
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    MAIN_DB_HOST: dbHost,
    MAIN_DB_PORT: std.toString(dbPort),
    MAIN_DB_USERNAME: dbUser,
    MAIN_DB_DATABASE: database,
    MESSAGE_DB_HOST: dbHost,
    MESSAGE_DB_PORT: std.toString(dbPort),
    MESSAGE_DB_USERNAME: messageDbUser,
    MESSAGE_DB_DATABASE_NAME_PREFIX: messageDbPrefix,
    POSTAL_WEB_HOSTNAME: webHostname,
    POSTAL_WEB_PROTOCOL: webProtocol,
    POSTAL_SMTP_HOSTNAME: smtpHostname,
    // The signing key is a FILE Postal reads, so the Secret is mounted as well as
    // read into the environment.
    POSTAL_SIGNING_KEY_PATH: '/secrets/SIGNING_KEY',
    // The image binds 127.0.0.1 out of the box, which answers nothing from
    // outside the pod.
    WEB_SERVER_DEFAULT_BIND_ADDRESS: '0.0.0.0',
    WEB_SERVER_DEFAULT_PORT: '5000',
    // The image's entrypoint blocks until these answer, which is what keeps the
    // container off a database that is still initialising.
    WAIT_FOR_TARGETS: dbHost + ':' + std.toString(dbPort),
    WAIT_FOR_TIMEOUT: '120',
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(5000)
  + kurly.servicePort(5000)
  + kurly.args(['postal', 'web-server'])
  + kurly.env(baseEnv + env)
  + kurly.envFromSecret(secretName)
  + kurly.secretMount(secretName, '/secrets')
  // The image's own account, uid 999.
  + kurly.runAs(999, gid=999, fsGroup=999)
  // The ruby the image ships carries FILE CAPABILITIES, and execve refuses a
  // binary whose file capabilities the bounding set does not cover: dropping ALL
  // makes running it impossible rather than unprivileged. What is reported is
  // "/usr/bin/env: 'ruby': Operation not permitted", naming the interpreter as if
  // it were missing from the image, and it happens in the INIT container, so the
  // pod shows Init:Error and never reaches anything that logs about Postal.
  // no_new_privs has to go too, or the exec cannot keep what the file grants. The
  // application still runs as 999.
  + kurly.keepCapabilities()
  + kurly.allowPrivilegeEscalation()
  // Rails keeps its pidfile, caches and uploaded bodies inside its own tree, and
  // the root filesystem stays read-only.
  + kurly.scratch('/opt/postal/app/tmp', '256Mi')
  + kurly.scratch('/opt/postal/app/log', '128Mi')
  + kurly.scratch('/tmp', '128Mi')
  // Postal migrates nothing on start: the schema is created by `postal
  // initialize`, which is idempotent, so it runs before every start and brings a
  // fresh database up without a manual step.
  + kurly.initContainer({
    name: 'initialize',
    image: image,
    args: ['postal', 'initialize'],
    envFrom: [{ secretRef: { name: secretName } }],
    env: [{ name: k, value: baseEnv[k] } for k in std.objectFields(baseEnv)],
    volumeMounts: [{ name: secretName, mountPath: '/secrets', readOnly: true }],
  })
  // Probe by connection: every path the web server answers redirects to the login
  // when signed out, and the login itself is served under the configured
  // webHostname — a probe following either starts failing on a configuration
  // change that has nothing to do with the pod being alive.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 30 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
