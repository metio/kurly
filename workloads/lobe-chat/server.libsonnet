// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// lobe-chat — a LobeChat server (a self-hosted, open-source AI chat UI supporting many LLM
// providers, plugins and multimodal input). A plain composable kurly.http workload on the official
// image. In its default mode conversations are stored client-side in the browser, so the server
// holds no data — a plain, horizontally scalable Deployment. Import it and render with kurly.list:
//
//   local lobechat = import 'github.com/metio/kurly/workloads/lobe-chat/server.libsonnet';
//   kurly.list(lobechat())
//
// Serves the web app on :3210 — compose an exposure onto it.
//
// PROVIDERS & SECRETS: point LobeChat at your LLM providers with the documented environment
// variables (OPENAI_API_KEY, OLLAMA_PROXY_URL, ACCESS_CODE, …). kurly authors no Secret; pass
// non-secret settings via env, and provide any API keys through a Secret referenced with your own
// envFrom (compose kurly.envFromSecret on).
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='lobe-chat',
  image='docker.io/lobehub/lobe-chat:latest@sha256:b2d2454525523d9f0a19c79661f83ec45f13363dbadd5c1180887e77af35d872',
  replicas=2,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(3210)
  + kurly.servicePort(3210)
  + kurly.env(env)
  + kurly.runAs(1001, gid=1001, fsGroup=1001)
  + kurly.writableRootFilesystem()
  + kurly.scratch('/tmp', '128Mi')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
