// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// code-server — a code-server instance (VS Code running in the browser, on a remote
// server). A plain composable kurly.http workload on the official image: your
// projects, extensions, and settings live on a PersistentVolume. Import it and
// render with kurly.list:
//
//   local codeServer = import 'github.com/metio/kurly/workloads/code-server/server.libsonnet';
//   kurly.list(codeServer())
//
// Serves the editor on :8080 — compose an exposure onto it.
//
// AUTH: code-server reads its PASSWORD (or HASHED_PASSWORD) from the environment.
// kurly authors no Secret; provide one holding PASSWORD, pulled in via envFrom.
//
// Single writer: your workspace lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='code-server',
  image='docker.io/codercom/code-server:4.129.0',
  storageSize='10Gi',
  storageClass=null,
  // The Secret holding PASSWORD (kurly mints none), via envFrom.
  secretName='code-server-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.envFromSecret(secretName)
  + kurly.env({ PORT: '8080' } + env)
  // The image runs as uid 1000 (coder); pin it and its fsGroup so the workspace
  // volume is writable and the restricted posture admits the pod.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/home/coder', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/healthz', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/healthz', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
