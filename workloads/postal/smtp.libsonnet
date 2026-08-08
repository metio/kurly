// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// postal-smtp — the Postal SMTP server (the door applications hand their mail in
// at, and the one incoming bounces arrive on). It runs the same official image as
// the `server` stage, wired to the same databases and the same Secret. Import it
// alongside the server and render with kurly.list:
//
//   local smtp = import 'github.com/metio/kurly/workloads/postal/smtp.libsonnet';
//   kurly.list(smtp())
//
// Deploy it after `server`, which creates the schema it reads.
//
// The Service publishes :25 and the container listens on :2525. The image gives
// ruby the cap_net_bind_service file capability so it can take :25 directly, but
// only a container that keeps capabilities can use it — listening high and
// mapping the Service port keeps the hardened default instead. Whatever reaches
// this from outside the cluster (a LoadBalancer, a Gateway TCPRoute) publishes
// :25 the same way; SMTP is not HTTP, so the expose recipes do not apply.
//
// Stateless: it writes what it accepts to the database, so scale it with
// kurly.replicas.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './smtp.image', '\n');

function(
  name='postal-smtp',
  image=defaultImage,
  webHostname='postal.example.com',
  webProtocol='https',
  // The banner this server greets a client with, and the name its own delivery
  // attempts announce.
  smtpHostname='postal.example.com',
  // The port the container listens on. Deliberately above 1024: binding :25 needs
  // a capability the hardened default drops.
  port=2525,
  // The port the Service publishes, which is what a client connects to.
  servicePort=25,
  dbHost='postal-db',
  dbPort=3306,
  database='postal',
  dbUser='postal',
  messageDbUser='postal',
  messageDbPrefix='postal',
  // The same Secret the server reads, holding MAIN_DB_PASSWORD,
  // MESSAGE_DB_PASSWORD, RAILS_SECRET_KEY and SIGNING_KEY.
  secretName='postal',
  replicas=1,
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(port)
  + kurly.servicePort(servicePort)
  + kurly.args(['postal', 'smtp-server'])
  + kurly.env(
    {
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
      POSTAL_SIGNING_KEY_PATH: '/secrets/SIGNING_KEY',
      SMTP_SERVER_DEFAULT_BIND_ADDRESS: '0.0.0.0',
      SMTP_SERVER_DEFAULT_PORT: std.toString(port),
      WAIT_FOR_TARGETS: dbHost + ':' + std.toString(dbPort),
      WAIT_FOR_TIMEOUT: '120',
    } + env
  )
  + kurly.envFromSecret(secretName)
  + kurly.secretMount(secretName, '/secrets')
  + kurly.runAs(999, gid=999, fsGroup=999)
  + kurly.scratch('/opt/postal/app/tmp', '256Mi')
  + kurly.scratch('/opt/postal/app/log', '128Mi')
  + kurly.scratch('/tmp', '128Mi')
  // SMTP is a conversation, not a request: the probe opens a connection and
  // leaves, which is exactly what a client does before it says anything.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 30 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
