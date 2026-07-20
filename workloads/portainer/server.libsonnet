// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// portainer — a Portainer CE server (a self-hosted management UI for Docker and Kubernetes). A
// plain composable kurly.http workload on the official image; its database and settings live on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local portainer = import 'github.com/metio/kurly/workloads/portainer/server.libsonnet';
//   kurly.list(portainer(serviceAccountName='portainer'))
//
// Serves the web UI on :9000 (HTTP) — compose an exposure onto it. Portainer also listens on
// :8000 for Edge agent tunnels and :9443 for its own TLS; this workload publishes only the plain
// HTTP UI port and lets an exposure terminate TLS.
//
// MANAGING THE CLUSTER: to administer the cluster it runs in, Portainer needs a ServiceAccount
// bound to a ClusterRole with the permissions you want it to have (cluster-admin for full
// control). kurly authors no RBAC and mints no ServiceAccount that grants cluster access; create
// the ServiceAccount and its (Cluster)RoleBinding yourself and pass its name as
// serviceAccountName. Left null, Portainer runs with the namespace default and can manage only
// what that account can.
//
// Single instance: the database lives on a ReadWriteOnce volume, so one replica, recreated
// (never rolled) to keep two instances off the same database.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
function(
  name='portainer',
  image='docker.io/portainer/portainer-ce:2.21.4',
  serviceAccountName=null,
  storageSize='1Gi',
  storageClass=null,
  env={},
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(9000)
  + kurly.servicePort(9000)
  + kurly.env(env)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.readinessProbe({ httpGet: { path: '/', port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + (if serviceAccountName == null then {} else kurly.serviceAccount(serviceAccountName))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
