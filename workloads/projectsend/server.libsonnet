// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// projectsend — a ProjectSend server (a self-hosted, private file-sharing app: upload files
// and assign them to specific clients, who log in to download — a client-portal alternative
// to public file hosts). A plain composable kurly.http workload on the LinuxServer.io image,
// backed by an external MySQL/MariaDB, with its config and uploads on a PersistentVolume.
// Import it, point it at a database, and render with kurly.list:
//
//   local projectsend = import 'github.com/metio/kurly/workloads/projectsend/server.libsonnet';
//   kurly.list(projectsend())
//
// Serves the web app on :80 — compose an exposure onto it.
//
// DATABASE: ProjectSend stores metadata in MySQL/MariaDB, configured through its web
// installer on first run; pair it with a mysql-cluster named projectsend-db.
//
// LINUXSERVER IMAGE: the s6-overlay init runs as root and drops to the PUID/PGID user, so
// this runs as root with a writable root filesystem — kurly keeps the rest of the hardening.
//
// Single writer: uploads and config live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='projectsend',
  image='lscr.io/linuxserver/projectsend:2021.12.10',
  storageSize='20Gi',
  storageClass=null,
  puid=1000,
  pgid=1000,
  timezone='UTC',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  + kurly.env({ PUID: std.toString(puid), PGID: std.toString(pgid), TZ: timezone } + env)
  + kurly.rootUser()
  + kurly.writableRootFilesystem()
  + kurly.store('/config', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
