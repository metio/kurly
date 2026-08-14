// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// triton-inference-server — NVIDIA's inference server: it serves models from a
// directory of them over HTTP and gRPC, with backends for TensorRT, ONNX,
// PyTorch, TensorFlow and Python. A plain composable kurly.http workload. Import
// it and render with kurly.list:
//
//   local triton = import 'github.com/metio/kurly/workloads/triton-inference-server/server.libsonnet';
//   kurly.list(triton(gpus=1))
//
// Serves inference on :8000 (HTTP) and :8001 (gRPC), and Prometheus metrics on
// :8002 — compose an exposure onto the HTTP port, and note that gRPC clients need
// a route that speaks it.
//
// THE MODEL REPOSITORY IS YOURS TO FILL AND AN EMPTY ONE IS FATAL BY DEFAULT.
// Triton loads every model under --model-repository at start and exits when it
// can load none, which is what an empty volume gives it. So this renders
// `--model-control-mode=explicit`: the server starts holding nothing and models
// are loaded through its API afterwards, which is the only shape that boots
// before somebody has put a model on the volume.
//
// GPUS ARE OPTIONAL HERE AND THE IMAGE IS NOT. `gpus=0` requests no device and
// serves on the CPU, which is real for ONNX and Python backends and slow for
// everything else; the image is CUDA-based either way, so a CPU-only deployment
// still pulls eight gigabytes and runs NVIDIA's entrypoint.
//
// Single writer: one model repository on a ReadWriteOnce volume, so one replica,
// recreated. A ReadWriteMany volume lets several servers share one repository,
// which is the shape to reach for when serving the same models to more traffic.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='triton-inference-server',
  image=defaultImage,
  // GPUs to request. Zero requests no device and serves on the CPU.
  gpus=0,
  storageSize='100Gi',
  storageClass=null,
  accessModes=['ReadWriteOnce'],
  // How models are loaded. 'explicit' starts with none and takes them through the
  // API; 'poll' and 'none' both load what is on the volume at start, and 'none'
  // exits when that is nothing.
  modelControlMode='explicit',
  extraArgs=[],
  env={},
  resources={ requests: { cpu: '1', memory: '4Gi' }, limits: { memory: '16Gi' } },
  labels={},
  annotations={},
)
  local gpuResource = if gpus > 0 then { 'nvidia.com/gpu': std.toString(gpus) } else {};

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8000)
  + kurly.servicePort(8000)
  + kurly.extraPort('grpc', 8001)
  + kurly.extraPort('metrics', 8002)
  + kurly.command(['tritonserver'])
  + kurly.args([
    '--model-repository=/models',
    '--model-control-mode=' + modelControlMode,
    '--http-port=8000',
    '--grpc-port=8001',
    '--metrics-port=8002',
  ] + extraArgs)
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/models', storageSize, accessModes=accessModes, storageClass=storageClass)
  + kurly.scratch('/tmp', '4Gi')
  // The backends allocate shared memory between the server and their worker
  // processes, and the default 64MB an emptyDir-less pod gets is not enough.
  + kurly.scratch('/dev/shm', '2Gi')
  // Loading a model repository of any size takes longer than a liveness probe
  // should wait, and /v2/health/ready is false until every model it was told to
  // load is loaded.
  + kurly.startupProbe({ httpGet: { path: '/v2/health/ready', port: 'http' }, periodSeconds: 15, failureThreshold: 80 })
  + kurly.readinessProbe({ httpGet: { path: '/v2/health/ready', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/v2/health/live', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}) + gpuResource,
    limits=std.get(resources, 'limits', {}) + gpuResource,
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
