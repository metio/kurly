// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// searxng — a SearXNG server (a privacy-respecting, self-hosted metasearch engine that
// aggregates results from many search services without tracking you). A plain composable
// kurly.http workload on the official image. Its behaviour is its settings.yml, mounted as
// a ConfigMap; it keeps no persistent state of its own. Import it, pass your settings, and
// render with kurly.list:
//
//   local searxng = import 'github.com/metio/kurly/workloads/searxng/server.libsonnet';
//   kurly.list(searxng(baseUrl='https://search.example.com'))
//
// Serves the search UI and API on :8080 — compose an exposure onto it.
//
// SECRET: SearXNG needs a server secret. kurly authors no Secret; set SEARXNG_SECRET from a
// Secret via envFrom (it overrides settings.yml's server.secret_key at runtime).
//
// SETTINGS: `settings` is SearXNG's own settings.yml schema, mounted verbatim — kurly does
// not model it. The default enables JSON output and binds all interfaces; replace or extend
// it to tune engines, UI and limits. A busy instance also wants a Valkey/Redis for the
// limiter (point settings.redis.url at it).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

local defaultSettings = {
  use_default_settings: true,
  server: {
    bind_address: '0.0.0.0',
    port: 8080,
    secret_key: 'change-me-via-SEARXNG_SECRET',
    limiter: false,
  },
  search: { formats: ['html', 'json'] },
};

function(
  name='searxng',
  image='docker.io/searxng/searxng:2026.7.9-b512eaa27',
  // The public URL (SearXNG builds absolute links from it).
  baseUrl=null,
  settings=defaultSettings,
  // The Secret holding SEARXNG_SECRET (kurly mints none), via envFrom.
  secretName='searxng-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseEnv = if baseUrl == null then {} else { SEARXNG_BASE_URL: baseUrl };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(2)
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.config({ 'settings.yml': std.manifestYamlDoc(settings) }, mountPath='/etc/searxng')
  + kurly.envFromSecret(secretName)
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.readinessProbe({ httpGet: { path: '/healthz', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
