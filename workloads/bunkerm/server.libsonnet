// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// bunkerm — an MQTT broker with a management interface: Eclipse Mosquitto and a
// web dashboard for its clients, ACLs and dynamic-security roles in one image, so
// the broker can be administered without editing configuration files by hand. A
// plain composable kurly.http workload. Import it and render with kurly.list:
//
//   local bunkerm = import 'github.com/metio/kurly/workloads/bunkerm/server.libsonnet';
//   kurly.list(bunkerm())
//
// TWO PORTS, AND ONLY ONE OF THEM IS HTTP. :2000 serves the dashboard and its API
// and is the Service's http port; :1900 is the MQTT listener itself, which is a
// raw TCP protocol and needs a TCP route rather than the HTTP exposure the
// dashboard takes. Publishing the dashboard does not publish the broker, and a
// client cannot speak MQTT to an HTTPRoute.
//
// THE API KEY IS GENERATED ON FIRST START AND KEPT ON THE VOLUME. The dashboard
// authenticates against a key at /nextjs/data/.api_key: supplied through `apiKey`
// it is used and persisted, and left unset the entrypoint generates a random one
// on the first boot and reuses it afterwards. A generated key is unknown to the
// deployment until it is read out of the volume, so a deployment that wants to
// automate against the API should set one.
//
// Single writer: the broker's persistence, the password file and that key live on
// one ReadWriteOnce volume, so one replica, recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='bunkerm',
  image=defaultImage,
  storageSize='5Gi',
  storageClass=null,
  // A Secret carrying API_KEY. Left unset, the entrypoint generates one on the
  // first start and keeps it on the volume.
  secretName=null,
  env={},
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(2000)
  + kurly.servicePort(2000)
  + kurly.extraPort('mqtt', 1900)
  + kurly.env(env)
  // THE ENTRYPOINT CHOWNS AND CHMODS BEFORE ANYTHING RUNS — the password file,
  // the log directories, the dashboard's data directory — and supervisord then
  // starts mosquitto, nginx and the API under their own users. A pod pinned to an
  // unprivileged uid cannot do any of that, and nginx and mosquitto both write
  // inside the image, so the read-only root filesystem has to go too.
  + kurly.runAs(0, gid=0)
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  + kurly.writableRootFilesystem()
  + kurly.store('/nextjs/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '128Mi')
  + (if secretName != null then kurly.envFromSecret(secretName) else {})
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
