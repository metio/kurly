// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// rabbitmq — a RabbitMQ server (a widely-used, self-hosted message broker implementing AMQP
// and other messaging protocols). A plain composable kurly.http workload on the official
// management image; the broker speaks AMQP on :5672 (not HTTP) and its data lives on a
// PersistentVolume. Import it, point it at its credentials, and render with kurly.list:
//
//   local rabbitmq = import 'github.com/metio/kurly/workloads/rabbitmq/server.libsonnet';
//   kurly.list(rabbitmq())
//
// Serves AMQP on :5672 — reached in-cluster (rabbitmq:5672). The management UI runs on :15672,
// a separate port that needs its own Service.
//
// SECRET: RabbitMQ reads RABBITMQ_DEFAULT_USER and RABBITMQ_DEFAULT_PASS from the environment.
// kurly authors no Secret; provide one holding them, via envFrom.
//
// Single writer: the data lives on a ReadWriteOnce volume, so one replica, recreated. This is
// a single node, not a RabbitMQ cluster.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='rabbitmq',
  image='docker.io/library/rabbitmq:4.0.4-management',
  storageSize='10Gi',
  storageClass=null,
  secretName='rabbitmq-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(5672)
  + kurly.servicePort(5672)
  + kurly.envFromSecret(secretName)
  + kurly.env(env)
  + kurly.runAs(999, gid=999, fsGroup=999)
  + kurly.store('/var/lib/rabbitmq', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
