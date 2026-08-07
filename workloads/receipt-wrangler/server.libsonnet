// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// receipt-wrangler — a Receipt Wrangler server (scan or upload a receipt, have it
// categorised, and split what it cost between the people who shared it). A
// composable kurly.http workload backed by an EXTERNAL PostgreSQL (the
// cnpg-cluster workload provides one) and an EXTERNAL Redis (the valkey workload
// provides one), with uploaded receipt images on a PersistentVolume. Import it and
// render with kurly.list:
//
//   local receiptWrangler = import 'github.com/metio/kurly/workloads/receipt-wrangler/server.libsonnet';
//   kurly.list(receiptWrangler())
//
// Serves the web app on :80 — compose an exposure onto it.
//
// REDIS IS NOT OPTIONAL. The API runs its task queue (asynq) in-process and exits
// fatally when it cannot reach Redis, so a deployment without one never starts,
// whatever the database says.
//
// Single writer: uploaded receipt images on a ReadWriteOnce volume, so one
// replica, recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='receipt-wrangler',
  image=defaultImage,
  // Uploaded receipt images and the rendered reports beside them.
  storageSize='10Gi',
  storageClass=null,
  // The PostgreSQL it connects to. The non-secret coordinates are env; the
  // password lives in the Secret.
  dbHost='receipt-wrangler-db-rw',
  dbPort=5432,
  database='receipt-wrangler',
  dbUser='receipt-wrangler',
  // The Redis the embedded asynq worker and scheduler use.
  redisHost='receipt-wrangler-cache-headless',
  redisPort=6379,
  // The Secret holding DB_PASSWORD, SECRET_KEY (signs sessions) and
  // ENCRYPTION_KEY (encrypts the mail-account credentials it polls receipts
  // from). The API refuses to start without the latter two.
  secretName='receipt-wrangler',
  env={},
  resources={ requests: { cpu: '250m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env(
    {
      DB_ENGINE: 'postgresql',
      DB_HOST: dbHost,
      DB_PORT: std.toString(dbPort),
      DB_NAME: database,
      DB_USER: dbUser,
      REDIS_HOST: redisHost,
      REDIS_PORT: std.toString(redisPort),
    } + env
  )
  + kurly.envFromSecret(secretName)
  // A Service named after this workload makes Kubernetes inject
  // RECEIPT_WRANGLER_PORT as a tcp:// URL, and a cache Service called redis
  // injects REDIS_PORT the same way — which this API parses as an integer and
  // dies on. Turn the links off rather than depend on the override order.
  + kurly.disableServiceLinks()
  // The entrypoint runs the Go API and nginx side by side as root: nginx binds
  // :80 and drops to its own account, which it can only do starting from root.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  // nginx keeps its pid, logs and temporary bodies inside the image's own tree,
  // and the API writes its log files beside its binary.
  + kurly.writableRootFilesystem()
  + kurly.store('/app/receipt-wrangler-api/data', storageSize, storageClass=storageClass)
  // The first boot migrates the schema before nginx has anything to proxy to.
  + kurly.startupProbe({ httpGet: { path: '/', port: 'http' }, failureThreshold: 30, periodSeconds: 10 })
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
