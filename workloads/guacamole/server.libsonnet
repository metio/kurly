// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// guacamole — an Apache Guacamole server (a clientless remote-desktop gateway: reach RDP, VNC
// and SSH machines from a browser, no plugins). Guacamole is TWO processes — the web app and
// the guacd proxy daemon it talks to — so this runs guacd as a SIDECAR in the same pod, reached
// on localhost, alongside the web container; it is backed by an external PostgreSQL or MySQL.
// Import it, point it at a database, and render with kurly.list:
//
//   local guacamole = import 'github.com/metio/kurly/workloads/guacamole/server.libsonnet';
//   kurly.list(guacamole())
//
// Serves the web app on :8080 — compose an exposure onto it (Guacamole is served under /guacamole
// unless you set the webapp context).
//
// DATABASE & SECRETS: the web app reads its database connection (POSTGRESQL_* or MYSQL_*) from
// the environment and expects the schema to be initialised. kurly authors no Secret; provide one
// holding the connection, via envFrom. Pairs with a cnpg-cluster named guacamole-db.
//
// Stateless: connections and users live in the database, so this is a plain rolling Deployment.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');

function(
  name='guacamole',
  image='docker.io/guacamole/guacamole:1.5.5',
  guacdImage='docker.io/guacamole/guacd:1.5.5',
  replicas=2,
  secretName='guacamole-secrets',
  env={},
  resources={ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '1Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8080)
  + kurly.servicePort(8080)
  + kurly.envFromSecret(secretName)
  // The web app finds guacd in its own pod, on localhost.
  + kurly.env({ GUACD_HOSTNAME: 'localhost', GUACD_PORT: '4822' } + env)
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.writableRootFilesystem()
  // guacd — the proxy daemon that speaks the remote-desktop protocols — as a sidecar. It
  // inherits the pod's security posture; the web container reaches it at localhost:4822.
  + kurly.sidecar({
    name: 'guacd',
    image: guacdImage,
    ports: [{ containerPort: 4822, name: 'guacd', protocol: 'TCP' }],
    readinessProbe: { tcpSocket: { port: 4822 } },
    livenessProbe: { tcpSocket: { port: 4822 } },
    resources: { requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
