// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// sglang — a serving runtime for large language models: it loads one model onto
// the GPUs of the node it lands on and answers an OpenAI-compatible API in front
// of it. A plain composable kurly.http workload. Import it and render with
// kurly.list:
//
//   local sglang = import 'github.com/metio/kurly/workloads/sglang/server.libsonnet';
//   kurly.list(sglang(model='meta-llama/Llama-3.1-8B-Instruct', gpus=1))
//
// Serves the API on :30000 — compose an exposure onto it.
//
// IT DOES NOT RUN WITHOUT AN NVIDIA GPU. The image is built on CUDA and its
// entrypoint is NVIDIA's; `gpus` becomes an nvidia.com/gpu resource request, and
// a node without the device plugin leaves the pod Pending rather than starting it
// slowly. There is no CPU fallback worth offering: a model that fits in system
// memory still answers at a speed nobody would put in front of users.
//
// THE MODEL IS DOWNLOADED ON EVERY COLD START UNLESS YOU KEEP IT. `model` is a
// Hugging Face repository the server fetches at boot — tens of gigabytes for a
// mid-sized model — so `storageSize` mounts a cache at the path the Hugging Face
// libraries read, and a pod restarting without one downloads it all again.
//
// A GATED MODEL NEEDS A TOKEN. Many repositories require accepting a licence, and
// the server exits when the download is refused; `secretName` carries
// HF_TOKEN.
//
// Single writer: one model cache on a ReadWriteOnce volume, so one replica,
// recreated (never rolled). Serving more traffic means more of these, each with
// its own cache, behind something that spreads requests.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='sglang',
  image=defaultImage,
  // The Hugging Face repository to serve.
  model='Qwen/Qwen2.5-0.5B-Instruct',
  // GPUs to request. Rendered as an nvidia.com/gpu resource on both requests and
  // limits, which is the only way Kubernetes schedules a device.
  gpus=1,
  storageSize='100Gi',
  storageClass=null,
  // A Secret carrying HF_TOKEN, for a gated model.
  secretName=null,
  extraArgs=[],
  env={},
  resources={ requests: { cpu: '2', memory: '16Gi' }, limits: { memory: '64Gi' } },
  labels={},
  annotations={},
)
  local gpuResource = { 'nvidia.com/gpu': std.toString(gpus) };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(30000)
  + kurly.servicePort(30000)
  + kurly.command(['python3', '-m', 'sglang.launch_server'])
  + kurly.args([
    '--model-path=' + model,
    '--host=0.0.0.0',
    '--port=30000',
  ] + extraArgs)
  // HF_HOME points the Hugging Face libraries at the volume, which is what makes
  // the download survive a restart.
  + kurly.env({ HF_HOME: '/cache' } + env)
  + (if secretName != null then kurly.envFromSecret(secretName) else {})
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/cache', storageSize, storageClass=storageClass)
  // Loading a model onto the GPUs writes a compiled kernel cache and scratch
  // files, and the runtime uses shared memory between its workers.
  + kurly.scratch('/tmp', '8Gi')
  + kurly.scratch('/dev/shm', '8Gi')
  // A cold start downloads the model and then compiles kernels for the device it
  // found, which takes far longer than a liveness probe should wait.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 30, failureThreshold: 120 })
  + kurly.readinessProbe({ httpGet: { path: '/health', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}) + gpuResource,
    limits=std.get(resources, 'limits', {}) + gpuResource,
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
