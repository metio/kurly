// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// wildduck — a WildDuck server (an IMAP and POP3 mail server that keeps every
// message in MongoDB). A plain composable kurly.http workload on the official
// image. Import it, point it at MongoDB and Redis, and render with kurly.list:
//
//   local wildduck = import 'github.com/metio/kurly/workloads/wildduck/server.libsonnet';
//   kurly.list(wildduck())
//
// Serves the REST API on :8080 (compose an exposure onto it), IMAPS on :9993 and
// POP3S on :9995 — route the two mail ports as TCP, since IMAP and POP3 are not
// HTTP and no HTTPRoute carries them.
//
// STATELESS: mailboxes, messages and attachments live in MongoDB (GridFS) and the
// session state in Redis, so this workload owns no volume and scales out.
//
// DATABASE & SECRETS: WildDuck reads its whole configuration from the shipped TOML
// files, each value overridable by an APPCONF_<section>_<key> environment variable.
// The two connection strings carry passwords, so they come from a provided Secret
// via envFrom (kurly mints none) together with the API access token.
//
// The API binds 127.0.0.1 by default, which no probe and no Service can reach — the
// stage sets APPCONF_api_host to 0.0.0.0 so the container port is actually served.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='wildduck',
  image=defaultImage,
  replicas=1,
  // The Secret holding APPCONF_dbs_mongo, APPCONF_dbs_redis and
  // APPCONF_api_accessToken (kurly mints none), via envFrom.
  secretName='wildduck',
  // The hostname WildDuck announces in its IMAP/POP3 greetings and uses when it
  // builds message identifiers.
  hostname=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv =
    {
      APPCONF_api_host: '0.0.0.0',
      APPCONF_api_port: '8080',
      APPCONF_imap_host: '0.0.0.0',
      APPCONF_pop3_host: '0.0.0.0',
    }
    + (if hostname == null then {} else { APPCONF_emailDomain: hostname });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.extraPort('imaps', 9993)
  + kurly.extraPort('pop3s', 9995)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  // The image ships a `node` user at uid 1000 and installs nothing under it that
  // has to be written to, so the hardened posture stands as it is.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // The Service is named after the workload, so Kubernetes would inject
  // WILDDUCK_PORT as a tcp:// URL — and wild-config reads the environment.
  + kurly.disableServiceLinks()
  // Node writes temporary files while streaming attachments in and out of GridFS,
  // which the read-only root filesystem does not allow.
  + kurly.scratch('/tmp', '256Mi')
  // Probed by connection: every API path answers 401 without the access token, and
  // a probe on a 401 kills the pod forever.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
