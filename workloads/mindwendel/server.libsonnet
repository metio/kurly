// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mindwendel — a mindwendel server (a shared brainstorming board where a team
// collects ideas and upvotes them). A plain composable kurly.http workload on the
// official image: a Phoenix release on :4000 with its state in an external
// PostgreSQL and nothing on disk. Import it, point it at a database, and render
// with kurly.list:
//
//   local mindwendel = import 'github.com/metio/kurly/workloads/mindwendel/server.libsonnet';
//   kurly.list(mindwendel(urlHost='ideas.example.com'))
//
// Serves the board on :4000 — compose an exposure onto it.
//
// DATABASE: the defaults point at a CNPG cluster named `mindwendel-db` (its `-rw`
// Service). The entrypoint waits for the server to answer, runs the Ecto
// migrations, and only then starts Phoenix, so a first boot takes a while — that
// is what the startup probe's budget is for. `databaseSsl` is off by default
// because an in-namespace PostgreSQL commonly serves plaintext and the app
// refuses to connect when it is told to expect TLS that is not there; turn it on
// when the server has a certificate.
//
// SECRETS: SECRET_KEY_BASE (Phoenix signs sessions with it — sessions and stored
// data depend on it staying stable) and DATABASE_USER_PASSWORD are read from the
// environment. kurly authors no Secret; provide one holding both, pulled in via
// envFrom.
//
// FILE UPLOADS are off by default. Turning them on is not a flag on its own: the
// app stores attachments in S3-compatible object storage and encrypts them with a
// vault key, so `fileUpload=true` needs the OBJECT_STORAGE_* settings and a
// base64 VAULT_ENCRYPTION_KEY_BASE64 in the Secret. Defaulting it on would render
// a workload that cannot start.
//
// Stateless, but ONE replica by default: without libcluster the Phoenix PubSub is
// per node, so two pods serve the same board without seeing each other's ideas.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='mindwendel',
  image=defaultImage,
  dbHost='mindwendel-db-rw',
  dbName='mindwendel',
  dbUser='mindwendel',
  dbPort='5432',
  // Whether to speak TLS to the database. Off by default (see the header).
  databaseSsl=false,
  // The public host, port and scheme the app builds its board links from. It
  // refuses to start without a host, so this defaults to a localhost URL that
  // makes a default render boot — point it at the real host for a real
  // deployment.
  urlHost='localhost',
  urlPort='4000',
  urlScheme='http',
  // The Secret holding SECRET_KEY_BASE and DATABASE_USER_PASSWORD (kurly mints
  // none), via envFrom.
  secretName='mindwendel',
  // The locale new boards start in, and how many days a board survives after its
  // last use ('' keeps them forever).
  defaultLocale='en',
  removalAfterDays='30',
  // Attachments on ideas. Needs object storage and a vault key — see the header.
  fileUpload=false,
  // Extra environment (MW_AI_*, OBJECT_STORAGE_*, MW_FEATURE_*, …), merged over
  // the below. Anything sensitive belongs in the Secret, not a literal here.
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    DATABASE_HOST: dbHost,
    DATABASE_NAME: dbName,
    DATABASE_USER: dbUser,
    DATABASE_PORT: dbPort,
    DATABASE_SSL: (if databaseSsl then 'true' else 'false'),
    URL_HOST: urlHost,
    URL_PORT: urlPort,
    URL_SCHEME: urlScheme,
    // The port Phoenix binds. Stated rather than left to the app's own default,
    // because the fallback it would otherwise read is PORT — which Kubernetes
    // does not set here, but a consumer easily might.
    MW_ENDPOINT_HTTP_PORT: '4000',
    MW_DEFAULT_LOCALE: defaultLocale,
    MW_FEATURE_BRAINSTORMING_REMOVAL_AFTER_DAYS: removalAfterDays,
    MW_FEATURE_IDEA_FILE_UPLOAD: (if fileUpload then 'true' else 'false'),
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.port(4000)
  + kurly.servicePort(4000)
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  // The image runs as nobody; pin it so the restricted posture admits the pod.
  + kurly.runAs(65534, gid=65534, fsGroup=65534)
  // An Erlang release renders its runtime configuration into $RELEASE_TMP under
  // its own install tree on every boot, and the VM writes crash dumps to /tmp;
  // back both with emptyDirs so the root filesystem stays read-only.
  + kurly.scratch('/app/tmp', '64Mi')
  + kurly.scratch('/tmp', '64Mi')
  // The entrypoint waits for the database, migrates it, and only then listens, so
  // the startup budget covers a first boot; liveness and readiness are plain
  // socket checks. Probing by connection rather than by path: every page redirects
  // to the current locale, and a probe that follows a redirect is a probe that
  // fails the day the redirect changes.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 60 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10 })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' }, initialDelaySeconds: 30, periodSeconds: 30 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
