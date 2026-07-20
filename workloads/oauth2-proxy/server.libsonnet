// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// oauth2-proxy — an OAuth2 Proxy server (a reverse proxy and forward-auth service that puts an
// OAuth2/OIDC login in front of your other apps, delegating to a provider like Keycloak,
// authentik, Pocket ID, Google or GitHub). A plain composable kurly.http workload on the official
// image. It holds no state — sessions live in a signed cookie (or a shared Redis) — so it is a
// plain stateless Deployment. Import it, point it at its config, and render with kurly.list:
//
//   local oauth2proxy = import 'github.com/metio/kurly/workloads/oauth2-proxy/server.libsonnet';
//   kurly.list(oauth2proxy())
//
// Serves on :4180 — either front an app as a reverse proxy (OAUTH2_PROXY_UPSTREAMS) or wire it as
// a reverse proxy's forward-auth (nginx auth_request, Traefik forwardAuth) at /oauth2/auth.
//
// SECRETS: oauth2-proxy reads its provider settings, client id/secret and cookie secret from
// OAUTH2_PROXY_* environment variables. kurly authors no Secret; provide one holding them, via
// envFrom.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='oauth2-proxy',
  image='quay.io/oauth2-proxy/oauth2-proxy:v7.7.1',
  replicas=2,
  secretName='oauth2-proxy-secrets',
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(4180)
  + kurly.servicePort(4180)
  + kurly.envFromSecret(secretName)
  + kurly.env({ OAUTH2_PROXY_HTTP_ADDRESS: '0.0.0.0:4180' } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.readinessProbe({ httpGet: { path: '/ping', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/ping', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
