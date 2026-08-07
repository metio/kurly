// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// flowctl — a flowctl server (a self-service workflow execution platform with
// approvals, remote execution and scheduling). A plain composable kurly.http
// workload on the official image, backed by an external PostgreSQL, keeping its
// flow definitions and its execution logs on PersistentVolumes. Import it, point
// it at a database, and render with kurly.list:
//
//   local flowctl = import 'github.com/metio/kurly/workloads/flowctl/server.libsonnet';
//   kurly.list(flowctl())
//
// Serves the web interface, the API and /metrics on :7000 — compose an exposure
// onto it.
//
// CONFIGURATION IS ENVIRONMENT ONLY. Without a config.toml beside the binary,
// flowctl builds its whole configuration from FLOWCTL_-prefixed variables (`__`
// is the section separator) and then VALIDATES it, so a required setting left out
// stops the process rather than falling back to a default — which is why the
// stage writes the full block rather than the interesting half of it.
//
// THE KEYSTORE KEY IS BUILT AT START, from KEYSTORE_KEY in the Secret. flowctl
// wants one URL, `base64key://<32 bytes, base64url>`, and a Secret can only carry
// the key material — so the entrypoint composes the two and refuses to start
// without the key, rather than accepting the empty `base64key://` that gocloud
// reads as "generate a fresh random key", under which every stored flow secret
// becomes unreadable at the next restart and nothing says so.
//
// The schema install runs as an init container. It is idempotent, and it builds
// its own connection string from the discrete FLOWCTL_DB__ settings rather than
// FLOWCTL_DB__DSN, so those are what the stage sets.
//
// Single writer: flow definitions and logs live on ReadWriteOnce volumes, so one
// replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='flowctl',
  image=defaultImage,
  flowsSize='1Gi',
  flowsStorageClass=null,
  logsSize='2Gi',
  logsStorageClass=null,
  dbHost='flowctl-db-rw',
  dbPort='5432',
  dbName='flowctl',
  dbUser='flowctl',
  dbSslMode='disable',
  adminUser='flowctl_admin',
  // The public URL a browser reaches this install at. It is what the interface
  // builds links and OIDC redirects against, so a deployment behind an exposure
  // sets it; the default is only right on a port-forward.
  rootUrl='http://localhost:7000',
  // The Secret holding FLOWCTL_DB__PASSWORD, FLOWCTL_APP__ADMIN_PASSWORD and
  // KEYSTORE_KEY (kurly mints none), via envFrom.
  secretName='flowctl',
  // flowctl validates the email messenger before it does anything else — even
  // `install` refuses to run without a well-formed host, port, sender address
  // and connection count, whether or not any notification is ever sent. So they
  // carry defaults that pass validation and reach a mail relay named the way a
  // cluster usually names one; a deployment that wants notifications points
  // them at its own, and one that does not is not blocked from starting.
  smtpHost='localhost',
  smtpPort='25',
  // A reserved .invalid domain (RFC 2606): the validator demands a well-formed
  // address with a TLD, and a placeholder that cannot resolve is what keeps a
  // deployment that never configured mail from sending as somebody real.
  smtpFrom='flowctl@flowctl.invalid',
  smtpMaxConns='1',
  workers='10',
  flowExecutionTimeout='1h',
  timezone='UTC',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    FLOWCTL_DB__HOST: dbHost,
    FLOWCTL_DB__PORT: dbPort,
    FLOWCTL_DB__DBNAME: dbName,
    FLOWCTL_DB__USER: dbUser,
    FLOWCTL_DB__SSLMODE: dbSslMode,
    FLOWCTL_APP__ADDRESS: ':7000',
    FLOWCTL_APP__ADMIN_USERNAME: adminUser,
    FLOWCTL_APP__ROOT_URL: rootUrl,
    FLOWCTL_APP__FLOWS_DIRECTORY: '/app/flows',
    FLOWCTL_APP__MAX_FILE_UPLOAD_SIZE: '104857600',
    FLOWCTL_LOGGER__BACKEND: 'file',
    FLOWCTL_LOGGER__LOG_DIRECTORY: '/var/log/flowctl',
    // 0 is unlimited for both: no rotation, no deletion. A run's log is the
    // record of what an approval let happen, so nothing here throws one away
    // until an operator says how long they keep them.
    FLOWCTL_LOGGER__MAX_SIZE_BYTES: '0',
    FLOWCTL_LOGGER__RETENTION_TIME: '0s',
    FLOWCTL_LOGGER__SCAN_INTERVAL: '1h0m0s',
    FLOWCTL_SCHEDULER__WORKERS: workers,
    FLOWCTL_SCHEDULER__CRON_SYNC_INTERVAL: '5m0s',
    FLOWCTL_SCHEDULER__FLOW_EXECUTION_TIMEOUT: flowExecutionTimeout,
    FLOWCTL_SCHEDULER__DEFAULT_TIMEZONE: timezone,
    FLOWCTL_MESSENGERS__EMAIL__HOST: smtpHost,
    FLOWCTL_MESSENGERS__EMAIL__PORT: smtpPort,
    FLOWCTL_MESSENGERS__EMAIL__FROM_ADDRESS: smtpFrom,
    FLOWCTL_MESSENGERS__EMAIL__MAX_CONNS: smtpMaxConns,
    FLOWCTL_METRICS__ENABLED: 'true',
    FLOWCTL_METRICS__PATH: '/metrics',
  } + env;

  // The keystore URL is the key material with a scheme in front of it, so it is
  // assembled where the key exists — in the container — and the unset case is an
  // error rather than a silently ephemeral key.
  local run(subcommand) = [
    '/bin/sh',
    '-c',
    'export FLOWCTL_KEYSTORE__KEEPER_URL="base64key://${KEYSTORE_KEY:?KEYSTORE_KEY is unset: put 32 base64url-encoded bytes in the Secret}"; exec /app/flowctl ' + subcommand,
  ];

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(7000)
  + kurly.servicePort(7000)
  + kurly.command(run('start'))
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/app/flows', flowsSize, storageClass=flowsStorageClass)
  + kurly.store('/var/log/flowctl', logsSize, storageClass=logsStorageClass)
  // The root filesystem stays read-only; the executors stage a run's files under
  // /tmp.
  + kurly.scratch('/tmp')
  // The Service is named after the workload, so Kubernetes would inject
  // FLOWCTL_PORT=tcp://… into a process that reads every one of its settings from
  // a FLOWCTL_-prefixed variable.
  + kurly.disableServiceLinks()
  // The migrations, and the superadmin the first run creates. Idempotent, so it
  // runs before every start and brings a fresh database up without a manual step.
  + kurly.initContainer({
    name: 'install',
    image: image,
    command: run('install'),
    envFrom: [{ secretRef: { name: secretName } }],
    env: [{ name: k, value: baseEnv[k] } for k in std.objectFields(baseEnv)],
  })
  // Every page and every API route is behind a session or a token, so health is
  // a connection check rather than a request that would be answered 401.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
