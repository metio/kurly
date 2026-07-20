// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// traccar — a Traccar server (a self-hosted GPS tracking platform: it ingests position
// reports from a huge range of GPS devices and phone apps and shows them live on a map). A
// plain composable kurly.http workload on the official image. Its server settings are a
// traccar.xml file, mounted as a ConfigMap; with the default embedded H2 database its data
// lives on a PersistentVolume. Import it, pass your config, and render with kurly.list:
//
//   local traccar = import 'github.com/metio/kurly/workloads/traccar/server.libsonnet';
//   kurly.list(traccar())
//
// Serves the web app and API on :8082 — compose an exposure onto it.
//
// DEVICE PORTS: Traccar listens for device protocols on a wide range of extra TCP/UDP
// ports (5000-5150) — too many to publish by default. Compose kurly.extraPort for each
// protocol your devices use, e.g. + kurly.extraPort('gps103', 5001); the web app works
// without them.
//
// CONFIG: `configXml` is Traccar's traccar.xml, mounted verbatim. The default points the
// embedded H2 database at the data volume. Point it at an external PostgreSQL/MySQL (the
// database.* keys) to scale past the single embedded writer.
//
// Single writer: the H2 database and media live on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the files.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

// Traccar's traccar.xml, pointing the embedded H2 database at the data volume. Replace the
// database.* entries to use an external PostgreSQL/MySQL.
local defaultConfigXml = |||
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE properties SYSTEM "http://java.sun.com/dtd/properties.dtd">
  <properties>
    <entry key='config.default'>./conf/default.xml</entry>
    <entry key='database.driver'>org.h2.Driver</entry>
    <entry key='database.url'>jdbc:h2:/opt/traccar/data/database</entry>
    <entry key='database.user'>sa</entry>
    <entry key='database.password'></entry>
  </properties>
|||;

function(
  name='traccar',
  image='docker.io/traccar/traccar:6.14.5',
  storageSize='10Gi',
  storageClass=null,
  configXml=defaultConfigXml,
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(8082)
  + kurly.servicePort(8082)
  + kurly.config({ 'traccar.xml': configXml }, mountPath='/opt/traccar/conf')
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  + kurly.store('/opt/traccar/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
