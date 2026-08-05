// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// docspell/server — the Docspell REST server (the web UI and API of a document
// organiser that files and indexes scanned documents). A composable kurly.http
// workload backed by an EXTERNAL PostgreSQL — the cnpg-cluster workload provides
// one — which also holds the documents themselves, so this stage claims no volume.
// Import it and render with kurly.list:
//
//   local docspell = import 'github.com/metio/kurly/workloads/docspell/server.libsonnet';
//   kurly.list(docspell(baseUrl='https://docs.example.com'))
//
// Serves the UI and API on :7880 — compose an exposure onto it.
//
// RUN THE JOEX STAGE ALONGSIDE IT. The server only queues work; every upload is
// converted, OCR'd and indexed by a joex node, so a deployment without one accepts
// documents and never processes any of them.
//
// CONFIGURATION is entirely environment: Docspell maps a config key onto an env var
// by uppercasing it, turning a dot into `_` and a dash into `__`, so
// `docspell.server.backend.jdbc.url` is DOCSPELL_SERVER_BACKEND_JDBC_URL. The image
// deletes its bundled config file, so what is not set here is the built-in default.
//
// BIND ADDRESS: Docspell binds `localhost` unless told otherwise, which in a pod
// means the kubelet's probe and the Service both reach nothing — so 0.0.0.0 is set
// explicitly rather than left to the default.
//
// SIGNUP MODE defaults to Docspell's own `open`: anybody who can reach the URL can
// create an account. `invite` or `closed` is the choice to make before exposing it.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='docspell',
  image=defaultImage,
  // The public URL Docspell builds its links from.
  baseUrl=null,
  // The PostgreSQL it connects to. The non-secret coordinates are env; the password
  // lives in the Secret.
  jdbcUrl='jdbc:postgresql://docspell-db-rw:5432/docspell',
  dbUser='docspell',
  // 'open', 'invite' or 'closed'.
  signupMode='open',
  // The Secret holding DOCSPELL_SERVER_BACKEND_JDBC_PASSWORD (kurly mints none),
  // pulled in via envFrom.
  secretName='docspell',
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = if baseUrl == null then {} else { DOCSPELL_SERVER_BASE__URL: baseUrl };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.port(7880)
  + kurly.servicePort(7880)
  + kurly.env(
    baseEnv {
      DOCSPELL_SERVER_BIND_ADDRESS: '0.0.0.0',
      DOCSPELL_SERVER_BIND_PORT: '7880',
      DOCSPELL_SERVER_BACKEND_JDBC_URL: jdbcUrl,
      DOCSPELL_SERVER_BACKEND_JDBC_USER: dbUser,
      DOCSPELL_SERVER_BACKEND_SIGNUP_MODE: signupMode,
    } + env
  )
  + kurly.envFromSecret(secretName)
  // The image runs as root; the JVM does not need to, and the hardened default
  // refuses a container that would.
  + kurly.runAs(1000, gid=1000)
  // The JVM and the upload handling write into java.io.tmpdir, and nothing else
  // outside the image tree — so a scratch there keeps the root filesystem read-only.
  + kurly.scratch('/tmp')
  // A Service named after this workload makes Kubernetes inject DOCSPELL_SERVER_PORT
  // as `tcp://…`, which is exactly the config key Docspell reads its listen port from.
  + kurly.disableServiceLinks()
  // Database migrations run before it serves, so the first start is the slow one.
  + kurly.startupProbe({ httpGet: { path: '/api/info/version', port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ httpGet: { path: '/api/info/version', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/api/info/version', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
