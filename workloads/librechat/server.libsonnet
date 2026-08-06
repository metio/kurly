// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// librechat — a LibreChat server (one chat interface in front of many model
// providers, keeping the conversations, presets and uploaded files that go with
// them). A composable kurly.http workload on the official image, backed by an
// EXTERNAL MongoDB. Import it and render with kurly.list:
//
//   local librechat = import 'github.com/metio/kurly/workloads/librechat/server.libsonnet';
//   kurly.list(librechat(domain='https://chat.example.com'))
//
// Serves the web app on :3080 — compose an exposure onto it.
//
// DATABASE & SECRETS: MONGO_URI comes from a provided Secret via envFrom, together
// with the four key materials LibreChat signs and encrypts with — CREDS_KEY and
// CREDS_IV encrypt the provider API keys users store, JWT_SECRET and
// JWT_REFRESH_SECRET sign their sessions. Losing CREDS_KEY/CREDS_IV makes every
// stored provider key unreadable, so they belong in a Secret that outlives the pod
// rather than in the environment of one. kurly mints no Secret. Pairs with a
// mongodb-cluster named librechat-db.
//
// The model API keys themselves are NOT set here: which providers an instance
// talks to is a deployment decision, so pass them through `env` or add them to the
// same Secret.
//
// Single writer: uploaded files and generated images on ReadWriteOnce volumes, so
// one replica, recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='librechat',
  image=defaultImage,
  // Files users upload (and what a RAG pipeline reads back).
  uploadsSize='10Gi',
  // Avatars and images the model providers generate, served to the browser.
  imagesSize='10Gi',
  storageClass=null,
  // The public URL a browser reaches this at. LibreChat builds absolute links and
  // OAuth callbacks from it, so it has no sane default and is left unset unless
  // given.
  domain=null,
  // The Secret holding MONGO_URI, CREDS_KEY, CREDS_IV, JWT_SECRET and
  // JWT_REFRESH_SECRET (envFrom). kurly authors none.
  secretName='librechat',
  // MeiliSearch powers conversation search and is a separate service; off unless a
  // consumer stands one up and sets MEILI_HOST/MEILI_MASTER_KEY through env.
  search=false,
  env={},
  resources={ requests: { cpu: '200m', memory: '1Gi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  local baseEnv =
    {
      HOST: '0.0.0.0',
      PORT: '3080',
      NODE_ENV: 'production',
      SEARCH: if search then 'true' else 'false',
    }
    + (if domain == null then {} else { DOMAIN_CLIENT: domain, DOMAIN_SERVER: domain });

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(3080)
  + kurly.servicePort(3080)
  + kurly.env(baseEnv + env)
  + kurly.envFromSecret(secretName)
  // The image declares USER node (1000:1000) and the volumes must be owned by it.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/app/uploads', uploadsSize, storageClass=storageClass)
  + kurly.store('/app/client/public/images', imagesSize, storageClass=storageClass)
  // Everything else the process writes sits inside its own install tree: winston
  // logs under api/logs, and npm — which is what the image's CMD runs — puts its
  // cache and its own error logs under $HOME.
  + kurly.scratch('/app/api/logs', '256Mi')
  + kurly.scratch('/home/node/.npm', '128Mi')
  + kurly.scratch('/tmp', '128Mi')
  // Probe by connection: the app answers a redirect to the login page at / and
  // requires a session beyond it, so an HTTP probe on a path is a claim about
  // authentication rather than about the server being up.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
