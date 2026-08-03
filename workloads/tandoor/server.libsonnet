// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// tandoor — a Tandoor Recipes server (a self-hosted recipe manager and meal planner with a smart
// shopping list). A plain composable kurly.http workload on the official image, backed by an
// external PostgreSQL; uploaded media (recipe images, imports) live on a PersistentVolume. Import
// it, point it at its backend, and render with kurly.list:
//
//   local tandoor = import 'github.com/metio/kurly/workloads/tandoor/server.libsonnet';
//   kurly.list(tandoor())
//
// Serves the web app on :8080 — compose an exposure onto it.
//
// BACKENDS & SECRETS: Tandoor reads SECRET_KEY and its PostgreSQL settings (POSTGRES_HOST,
// POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD) from the environment. kurly authors no Secret;
// provide one holding them, via envFrom. The defaults pair with a cnpg-cluster named tandoor-db.
//
// Single writer for media: the media volume is ReadWriteOnce, so one replica, recreated (never
// rolled) to keep two pods off the same mediafiles directory. Serve /media and /static through the
// exposure or a sidecar if you scale the app out with a shared (ReadWriteMany) volume instead.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');
function(
  name='tandoor',
  image=defaultImage,
  storageSize='5Gi',
  storageClass=null,
  secretName='tandoor',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  // The bundled nginx serves on TANDOOR_PORT, which defaults to :80.
  + kurly.port(80)
  + kurly.servicePort(8080)
  + kurly.envFromSecret(secretName)
  + kurly.env(env)
  // The image declares root, but it runs as an ordinary uid: its files are
  // world-readable and everything it writes is under a volume fsGroup owns.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // Everything is dropped and these are granted back by name — the
  // smallest set this image was observed to boot with.
  + kurly.addCapabilities(['CHOWN', 'SETGID', 'SETUID'])
  + kurly.writableRootFilesystem()
  + kurly.store('/opt/recipes/mediafiles', storageSize, storageClass=storageClass)
  // The first start migrates the schema and collects static files before it listens.
  // The Service is named after the app, so the Service-link environment defines
  // TANDOOR_PORT as a tcp:// URL — which its nginx template uses as a listen address.
  + kurly.disableServiceLinks()
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 45 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
