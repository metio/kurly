// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// warpgate — a Warpgate server (a smart SSH, HTTPS and database bastion: users
// connect to it with an ordinary client, authenticate once, and it proxies them to
// the targets they are allowed, recording the session). A plain composable
// kurly.http workload: its configuration, SQLite database, host keys and any
// recordings live on one PersistentVolume. Import it and render with kurly.list:
//
//   local warpgate = import 'github.com/metio/kurly/workloads/warpgate/server.libsonnet';
//   kurly.list(warpgate())
//
// Serves the admin UI and the HTTPS proxy on :8888 — compose an exposure onto it.
// SSH is a second port on the Service (:2222) and is not HTTP, so route it with a
// TCPRoute or a LoadBalancer rather than an Ingress.
//
// Single writer: one SQLite database and one set of host keys on a ReadWriteOnce
// volume, so one replica, recreated (never rolled). The host keys matter more than
// the database here — two instances with different keys make every client's
// known_hosts check fail, which is indistinguishable from the attack it exists to
// detect.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='warpgate',
  image=defaultImage,
  storageSize='10Gi',
  storageClass=null,
  httpPort=8888,
  sshPort=2222,
  // The Secret holding WARPGATE_ADMIN_PASSWORD, which the setup step reads to
  // create the first administrator. kurly authors no Secret — and this one is read
  // ONCE, at first setup: changing it later does not change the password, because
  // by then it lives hashed in Warpgate's own database.
  secretName='warpgate',
  // Session recording is off by default: it writes the contents of every proxied
  // session to the volume, which is a storage decision and a privacy one, and
  // neither is kurly's to make for somebody.
  recordSessions=false,
  env={},
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(httpPort)
  + kurly.servicePort(httpPort)
  + kurly.extraPort('ssh', sshPort)
  + (if env == {} then {} else kurly.env(env))
  // The image already runs as its own unprivileged account, so nothing is relaxed
  // to reach the hardened posture; fsGroup is what makes the volume writable.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  // `warpgate run` refuses to start without a configuration file, and the only
  // thing that writes one is a setup step — interactive by default, which a pod
  // cannot answer. unattended-setup writes the same file from flags, and it also
  // mints the SSH host keys, so this has to happen before the server starts and
  // exactly once: rerunning it would issue NEW host keys and break every client
  // that has already trusted the old ones.
  //
  // The guard is therefore not an optimisation. It is what makes the difference
  // between a restart and a fresh identity.
  + kurly.initContainer({
    name: 'setup',
    image: image,
    command: [
      'sh',
      '-c',
      'test -f /data/warpgate.yaml || warpgate --config /data/warpgate.yaml unattended-setup'
      + ' --data-path /data --http-port ' + httpPort + ' --ssh-port ' + sshPort
      + (if recordSessions then ' --record-sessions' else ''),
    ],
    envFrom: [{ secretRef: { name: secretName } }],
    volumeMounts: [{ name: 'store', mountPath: '/data' }],
  })
  // The image ships its own healthcheck subcommand, which knows what a healthy
  // Warpgate is better than a request to a page does — the HTTPS port answers TLS,
  // so an httpGet probe would have to be told to speak it and would still only
  // prove the listener is up.
  + kurly.readinessProbe({ exec: { command: ['warpgate', '--config', '/data/warpgate.yaml', 'healthcheck'] } })
  + kurly.livenessProbe({ exec: { command: ['warpgate', '--config', '/data/warpgate.yaml', 'healthcheck'] } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
