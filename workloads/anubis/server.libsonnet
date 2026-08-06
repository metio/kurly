// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// anubis — an Anubis server (it sits in FRONT of another service and makes every
// unrecognised client solve a proof-of-work challenge before the request is
// forwarded, which is what keeps a scraper fleet off an application that cannot
// take the load). A plain composable kurly.http workload on the official image.
// Import it and render with kurly.list:
//
//   local anubis = import 'github.com/metio/kurly/workloads/anubis/server.libsonnet';
//   kurly.list(anubis(target='http://forgejo:3000'))
//
// Serves the filtered traffic on :8923 — compose an exposure onto THIS workload
// and point it at the service it protects with `target`. One Anubis per
// protected service: it proxies to exactly one upstream.
//
// PROBES read /healthz on the metrics port (:9090), never the proxy port: a
// request to :8923 is answered by whatever `target` names, or by a challenge
// page, and neither says anything about Anubis being healthy.
//
// SECRET: ED25519_PRIVATE_KEY_HEX signs the challenge cookies. Anubis generates
// one when it is unset, which means every restart invalidates every pass issued
// so far and every replica issues passes the others reject — so the key is
// supplied, and it is what makes more than one replica work at all.
//
// Stateless: challenges live in memory, so no PersistentVolume.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='anubis',
  image=defaultImage,
  replicas=2,
  // The service Anubis forwards a passing request to — a URL reaching it from
  // inside the cluster, usually the protected workload's own Service.
  target='http://localhost:3923',
  // How much work a client has to do. Upstream's own Kubernetes example uses 4;
  // every increment doubles it, and it is paid by every human visitor too.
  difficulty=4,
  // The domain the challenge cookie is set for — the registrable domain, not the
  // host (`example.com`, not `git.example.com`). Unset leaves it host-only.
  cookieDomain=null,
  // Anubis marks the cookie Secure by default, which a browser then refuses to
  // store over plain HTTP; set false only where TLS never terminates in front.
  cookieSecure=true,
  // Serve a robots.txt disallowing every known scraper, for a backend whose own
  // robots.txt cannot be changed.
  serveRobotsTxt=true,
  // The Secret holding ED25519_PRIVATE_KEY_HEX (64 hex characters). kurly mints
  // no Secret; the consumer provides it.
  secretName='anubis',
  env={},
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8923)
  + kurly.servicePort(8923)
  // Prometheus metrics AND /healthz, which is why it is published rather than
  // left on localhost.
  + kurly.extraPort('metrics', 9090)
  + kurly.env(
    {
      BIND: ':8923',
      METRICS_BIND: ':9090',
      TARGET: target,
      DIFFICULTY: std.toString(difficulty),
      SERVE_ROBOTS_TXT: if serveRobotsTxt then 'true' else 'false',
      COOKIE_SECURE: if cookieSecure then 'true' else 'false',
    }
    + (if cookieDomain == null then {} else { COOKIE_DOMAIN: cookieDomain })
    + env
  )
  + kurly.envFromSecret(secretName)
  // The image runs as uid/gid 1000 already; nothing else about the hardened
  // default has to give — a single Go binary serving embedded assets writes
  // nowhere.
  + kurly.runAs(1000, gid=1000)
  + kurly.readinessProbe({ httpGet: { path: '/healthz', port: 'metrics' } })
  + kurly.livenessProbe({ httpGet: { path: '/healthz', port: 'metrics' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
