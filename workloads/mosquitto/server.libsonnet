// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// mosquitto — an Eclipse Mosquitto server (a lightweight, self-hosted MQTT message broker,
// the backbone of most IoT and home-automation setups). A composable kurly.http workload used
// here for its Deployment/Service plumbing, but Mosquitto speaks MQTT, not HTTP: it listens
// on :1883, its configuration is a mosquitto.conf mounted as a ConfigMap, and its persistence
// database lives on a PersistentVolume. Import it, pass your config, and render with
// kurly.list:
//
//   local mosquitto = import 'github.com/metio/kurly/workloads/mosquitto/server.libsonnet';
//   kurly.list(mosquitto())
//
// Serves MQTT on :1883 — reached in-cluster (mosquitto:1883) or exposed to devices (often a
// LoadBalancer), not through an HTTP ingress.
//
// CONFIG: `config` is Mosquitto's mosquitto.conf, mounted verbatim. The default allows
// anonymous clients and persists to the data volume — fine to start, but a real broker sets
// up authentication (a password_file or an auth plugin). WebSockets (:9001) need a listener in
// the config and a second Service.
//
// Single writer: the persistence database lives on a ReadWriteOnce volume, so one replica,
// recreated (never rolled) to keep two pods off the file.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');

local defaultConfig = |||
  listener 1883
  persistence true
  persistence_location /mosquitto/data/
  allow_anonymous true
|||;

function(
  name='mosquitto',
  image='docker.io/eclipse-mosquitto:2.0.20',
  storageSize='1Gi',
  storageClass=null,
  config=defaultConfig,
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(1883)
  + kurly.servicePort(1883)
  + kurly.config({ 'mosquitto.conf': config }, mountPath='/mosquitto/config')
  + kurly.env(env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/mosquitto/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
