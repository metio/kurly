// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// jelu — a Jelu server (a book tracker for the books you have read, are reading and
// want to read). A plain composable kurly.http workload on the official image: it
// keeps its embedded database and uploaded files on a PersistentVolume, so it needs
// no external database. Import it and render with kurly.list:
//
//   local jelu = import 'github.com/metio/kurly/workloads/jelu/server.libsonnet';
//   kurly.list(jelu())
//
// Serves the web UI and API on :11111 — compose an exposure onto it.
//
// The image ships the database under /database and the uploaded cover images and
// import files under /files; both are subpaths of the one volume.
//
// The Spring Boot application writes temporary files under /tmp and reads an optional
// configuration directory at /config, so both are scratch volumes and the rest of the
// root filesystem stays read-only.
//
// Service links are disabled: a Service named after this workload makes Kubernetes
// inject JELU_PORT as a tcp:// URL, which Spring's relaxed binding reads as
// configuration.
//
// Single writer: the database lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='jelu',
  image=defaultImage,
  storageSize='5Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '250m', memory: '768Mi' }, limits: { memory: '1536Mi' } },
  labels={},
  annotations={},
)
  // The uploaded images and imports live beside the database on the same volume.
  local extraDirs = {
    deployment+: { spec+: { template+: { spec+: {
      containers: [
        container { volumeMounts+: [
          { name: 'store', mountPath: '/files', subPath: 'files' },
        ] }
        for container in super.containers
      ],
    } } } },
  };

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(11111)
  + kurly.servicePort(11111)
  // The Lucene search index defaults to the working directory, which is where the
  // application's own jar lives — put it on the volume beside the database instead.
  // Binding jelu.lucene from the environment replaces the whole object, and its
  // indexAnalyzer is non-null, so the analyzer defaults are restated here.
  + kurly.env({
    JELU_LUCENE_DATADIRECTORY: '/database/lucene',
    JELU_LUCENE_INDEXANALYZER_MINGRAM: '3',
    JELU_LUCENE_INDEXANALYZER_MAXGRAM: '10',
    JELU_LUCENE_INDEXANALYZER_PRESERVEORIGINAL: 'true',
  } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.disableServiceLinks()
  // The JVM writes its temporary files under /tmp; the entrypoint reads an optional
  // Spring configuration directory at /config. Scratches there keep the rest of the
  // root filesystem read-only.
  + kurly.scratch('/tmp')
  + kurly.scratch('/config')
  + kurly.store('/database', storageSize, storageClass=storageClass)
  // A JVM plus the schema migration takes a while before anything listens.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10, failureThreshold: 60 })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + extraDirs
