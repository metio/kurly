// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// halo — a Halo server (a website and blog publishing platform with a plugin and
// theme system). A plain composable kurly.http workload keeping its work
// directory — the embedded H2 database, uploaded attachments, themes and plugins
// — on a PersistentVolume. Import it and render with kurly.list:
//
//   local halo = import 'github.com/metio/kurly/workloads/halo/server.libsonnet';
//   kurly.list(halo())
//
// Serves the site on :8090 — compose an exposure onto it.
//
// EXTERNAL URL: Halo builds absolute links (and the attachment URLs it stores)
// from halo.external-url. Left unset it guesses from the request, which is wrong
// behind a proxy that rewrites the Host; pass externalUrl once the hostname is
// known, before anything is published.
//
// DATABASE: the default is the embedded H2 file database inside the work
// directory — fine for one author, and what makes this workload deployable with
// nothing else in the namespace. Point SPRING_R2DBC_URL / SPRING_R2DBC_USERNAME /
// SPRING_R2DBC_PASSWORD / SPRING_SQL_INIT_PLATFORM at PostgreSQL through env or
// the Secret for anything larger; H2 has no second reader.
//
// SUPERADMIN: the initial administrator's password comes from the Secret named by
// secretName (HALO_SECURITY_INITIALIZER_SUPERADMINPASSWORD). Halo ships a
// PUBLISHED default for it, so supplying that Secret is the difference between an
// account you own and one anybody can log into. kurly authors no Secret.
//
// Single writer: the work directory lives on a ReadWriteOnce volume, so one
// replica, recreated (never rolled) — two JVMs on one H2 file is not a thing H2
// sorts out afterwards.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='halo',
  image=defaultImage,
  storageSize='10Gi',
  storageClass=null,
  // The public URL Halo builds links and attachment paths against. Null lets it
  // guess from the request — acceptable for a first bring-up, wrong the moment a
  // proxy sits in front.
  externalUrl=null,
  // Holds HALO_SECURITY_INITIALIZER_SUPERADMINPASSWORD, and any database
  // credentials when this is pointed away from the embedded H2 file.
  secretName='halo',
  env={},
  resources={ requests: { cpu: '250m', memory: '768Mi' }, limits: { memory: '1536Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8090)
  + kurly.servicePort(8090)
  // The image's own HALO_WORK_DIR is /root/.halo2, which only a root process can
  // write; the work directory moves onto the volume instead, and Spring's
  // optional config file location has to follow it or an operator's
  // application.yaml beside the data is never read.
  + kurly.env(
    {
      HALO_WORK_DIR: '/halo2',
      SPRING_CONFIG_LOCATION: 'optional:classpath:/;optional:file:/halo2/',
      SERVER_PORT: '8090',
    }
    + (if externalUrl == null then {} else { HALO_EXTERNAL_URL: externalUrl })
    + env
  )
  + (if secretName == null then {} else kurly.envFromSecret(secretName))
  // A Service named after the workload has Kubernetes inject HALO_PORT and
  // friends, which Spring's relaxed binding reads as halo.* configuration.
  + kurly.disableServiceLinks()
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/halo2', storageSize, storageClass=storageClass)
  // The JVM keeps its perf data and temporary files in /tmp.
  + kurly.scratch('/tmp', '256Mi')
  // A JVM that unpacks plugins and initialises the database on first boot takes
  // minutes, not seconds — that budget belongs in a startup probe, so the
  // liveness probe can stay tight afterwards.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 60 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
