// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// cannery — a Cannery server (an inventory for firearms, ammunition and range
// use: what is owned, how much ammunition is left, and what was shot when). A
// plain composable kurly.http workload on the official image: a Phoenix release
// on :4000 with all of its state in an external PostgreSQL, so it claims no
// volume. Import it, point it at a database, and render with kurly.list:
//
//   local cannery = import 'github.com/metio/kurly/workloads/cannery/server.libsonnet';
//   kurly.list(cannery(host='cannery.example.com'))
//
// Serves the web app on :4000 — compose an exposure onto it.
//
// DATABASE: the release migrates on start (automigrate is on in the production
// configuration), so a first boot against a fresh database is slower than the
// ones after it — that is what the startup budget is for. The connection string
// is DATABASE_URL and it carries the password, so it lives in the Secret rather
// than in env here; the defaults pair with a CNPG cluster named `cannery-db`.
//
// SECRETS: SECRET_KEY_BASE (Phoenix signs the session cookie with it — a value
// that changes on every restart signs everybody out), DATABASE_URL and the SMTP
// credentials are read from the environment. kurly authors no Secret; provide one
// holding them and it is pulled in via envFrom.
//
// MAIL IS NOT OPTIONAL: the production configuration REFUSES to start without
// SMTP_HOST, SMTP_USERNAME and SMTP_PASSWORD. Cannery invites users by email and
// confirms addresses by email, so an instance that cannot send mail cannot admit
// anybody past the first account. smtpHost is a parameter with a placeholder
// default so a default render boots; the credentials come from the Secret.
//
// HOST is the public domain the app builds its links and its invite mails from.
// It defaults to localhost, which makes a default render boot and is wrong for
// every real deployment.
//
// Stateless, and still ONE replica by default: Phoenix PubSub is per node without
// libcluster, so two pods do not see each other's live updates.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='cannery',
  image=defaultImage,
  // The public domain the browser reaches this instance at. Cannery builds its
  // links and its invite mails from it and refuses to start without one, so this
  // defaults to a value that boots rather than a value that is right.
  host='localhost',
  // The Secret holding SECRET_KEY_BASE, DATABASE_URL, SMTP_USERNAME and
  // SMTP_PASSWORD (kurly mints none), pulled in via envFrom.
  secretName='cannery',
  // The mail relay. The credentials belong in the Secret; only the host, port and
  // TLS switch are settings.
  smtpHost='localhost',
  smtpPort='587',
  smtpSsl=false,
  // The sender address and display name. Cannery derives the address from HOST
  // when it is not given, which is a mailbox that usually does not exist.
  emailFrom=null,
  emailName='Cannery',
  // Who may sign up: 'invite' (an existing user hands out an invite link) or
  // 'public'. Invite-only by default, because a public instance of a firearms
  // inventory is a decision, not a default.
  registration='invite',
  // The interface language: en_US, de, fr or es.
  locale='en_US',
  // The Ecto connection pool size.
  poolSize='10',
  replicas=1,
  // Extra environment, merged over the below. Anything sensitive belongs in the
  // Secret, not a literal here.
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(4000)
  + kurly.servicePort(4000)
  + kurly.envFromSecret(secretName)
  + kurly.env(
    {
      HOST: host,
      PORT: '4000',
      POOL_SIZE: poolSize,
      REGISTRATION: registration,
      LOCALE: locale,
      SMTP_HOST: smtpHost,
      SMTP_PORT: smtpPort,
      SMTP_SSL: (if smtpSsl then 'true' else 'false'),
      EMAIL_NAME: emailName,
      // An Elixir release renders its runtime vm.args and its boot files into the
      // release tree unless RELEASE_TMP names somewhere else; the root filesystem
      // is read-only here, so name the scratch.
      RELEASE_TMP: '/tmp',
    }
    + (if emailFrom == null then {} else { EMAIL_FROM: emailFrom })
    + env
  )
  // The image's USER is the NAME `nobody`, which kubelet cannot check against
  // runAsNonRoot — it refuses to start a container whose user is non-numeric — so
  // pin the uid and gid Alpine gives that account.
  + kurly.runAs(65534, gid=65534, fsGroup=65534)
  + kurly.scratch('/tmp', '256Mi')
  // The BEAM boots and the release migrates the database before it listens; a
  // liveness probe alone would restart it mid-migration. Probing by connection:
  // every page redirects an unauthenticated visitor to the sign-in form, and a
  // probe that follows a redirect fails the day the redirect changes.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 5, failureThreshold: 60 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
