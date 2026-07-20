// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// hollama — a Hollama server (a minimal, self-hosted web UI for Ollama and OpenAI-compatible LLMs).
// A plain composable kurly.http workload on the official image. Sessions and settings are stored
// client-side in the browser, so the server holds no data — a plain, horizontally scalable
// Deployment. Import it and render with kurly.list:
//
//   local hollama = import 'github.com/metio/kurly/workloads/hollama/server.libsonnet';
//   kurly.list(hollama())
//
// Serves the web app on :4173 — compose an exposure onto it. The browser talks to your Ollama /
// OpenAI endpoint directly; configure it in the UI.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='hollama',
  image='ghcr.io/fmaclen/hollama:latest@sha256:74999be7ac1cb23e72c81b9e21055aec20576f9ef67b394fe0eeb2e36c3a8b93',
  replicas=2,
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(4173)
  + kurly.servicePort(4173)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
