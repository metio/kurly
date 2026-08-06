// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// budget-board/client — the Budget Board web interface: a static bundle served by
// nginx, which also proxies /api/ to the server stage. A composable kurly.http
// workload with no state of its own. Import it and render with kurly.list:
//
//   local client = import 'github.com/metio/kurly/workloads/budget-board/client.libsonnet';
//   kurly.list(client())
//
// Serves the app on :6253 — this is the half a user's browser talks to, so
// compose the exposure onto THIS stage, and give the server stage the same
// address as its clientAddress.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './client.image', '\n');

function(
  name='budget-board-client',
  image=defaultImage,
  replicas=1,
  // The in-cluster host of the server stage. nginx proxies /api/ to it on :8080,
  // which the image's own template hard-codes, so this is a host, not a URL.
  serverHost='budget-board-server',
  port=6253,
  // The interface reads the same authentication switches as the server so its
  // login screen matches what the API will accept.
  oidcEnabled=false,
  oidcIssuer='',
  oidcClientId='',
  disableLocalAuth=false,
  disableNewUsers=false,
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(port)
  + kurly.servicePort(port)
  + kurly.env(
    {
      PORT: std.toString(port),
      VITE_SERVER_ADDRESS: serverHost,
      VITE_OIDC_ENABLED: std.toString(oidcEnabled),
      VITE_OIDC_PROVIDER: oidcIssuer,
      VITE_OIDC_CLIENT_ID: oidcClientId,
      VITE_DISABLE_LOCAL_AUTH: std.toString(disableLocalAuth),
      VITE_DISABLE_NEW_USERS: std.toString(disableNewUsers),
    } + env
  )
  // The entrypoint substitutes the environment into the nginx site config and
  // rewrites the bundle's own settings file in place, both inside the image's
  // tree, so the root filesystem cannot be read-only and the substitution runs as
  // the account that owns those files. nginx then drops its workers to the nginx
  // user, which is what needs these three capabilities back.
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.addCapabilities(['CHOWN', 'SETGID', 'SETUID'])
  // A Service in the namespace publishes <NAME>_PORT into every pod, and this
  // image takes PORT as the port to listen on.
  + kurly.disableServiceLinks()
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
