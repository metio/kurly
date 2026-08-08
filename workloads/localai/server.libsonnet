// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// localai — a LocalAI server (an OpenAI-compatible API in front of locally run
// language, image and audio models). A plain composable kurly.http workload on the
// official CPU image: models, downloaded backends and generated content live on a
// PersistentVolume, so it needs no external database. Import it and render with
// kurly.list:
//
//   local localai = import 'github.com/metio/kurly/workloads/localai/server.libsonnet';
//   kurly.list(localai())
//
// Serves the OpenAI-compatible API and the web UI on :8080 — compose an exposure
// onto it. The API is UNAUTHENTICATED unless an API key is configured
// (LOCALAI_API_KEY, from your own Secret via envFrom), so do not expose it
// publicly as it stands.
//
// MODELS: none are bundled. Pull one at runtime through the UI or the models
// endpoint, or set LOCALAI_AUTOLOAD_GALLERIES / preload environment variables —
// the first pull downloads gigabytes onto the volume, so size it for the models
// you intend to run. A model runs on the CPU here; a GPU needs one of upstream's
// accelerator images plus the matching device resources.
//
// Single writer: models and backends live on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='localai',
  image=defaultImage,
  storageSize='50Gi',
  storageClass=null,
  // The Secret holding LOCALAI_API_KEY and any other credentials (kurly mints
  // none), pulled in via envFrom. Null wires no Secret at all.
  secretName=null,
  env={},
  resources={ requests: { cpu: '500m', memory: '2Gi' }, limits: { memory: '8Gi' } },
  labels={},
  annotations={},
)
  local baseEnv = {
    LOCALAI_MODELS_PATH: '/models',
    LOCALAI_BACKENDS_PATH: '/backends',
    LOCALAI_GENERATED_CONTENT_DIR: '/data/generated',
    LOCALAI_UPLOAD_DIR: '/data/upload',
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  // A Service named localai injects LOCALAI_PORT=tcp://…, which the server reads
  // as its own listen address and then fails to bind.
  + kurly.disableServiceLinks()
  + (if secretName == null then {} else kurly.envFromSecret(secretName))
  + kurly.env(baseEnv + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/models', storageSize, storageClass=storageClass)
  + kurly.scratch('/backends')
  + kurly.scratch('/data')
  + kurly.scratch('/configuration')
  + kurly.scratch('/tmp')
  // Probe by connection: the API answers 401 once an API key is set, and a probe
  // on an authenticated path would then kill the pod for good.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  // The first start scans the model directory and may prepare backends, which
  // takes minutes on a cold volume.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 60 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
