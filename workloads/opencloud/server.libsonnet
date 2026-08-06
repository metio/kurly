// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// opencloud — an OpenCloud server (file sync and share with a web interface,
// WebDAV and desktop/mobile clients, run as ONE process that hosts every internal
// service). A plain composable kurly.http workload: the generated configuration
// and the stored files live on two PersistentVolumes. Import it and render with
// kurly.list:
//
//   local opencloud = import 'github.com/metio/kurly/workloads/opencloud/server.libsonnet';
//   kurly.list(opencloud(url='https://cloud.example.com'))
//
// Serves the web UI, WebDAV and the APIs on :9200 — compose an exposure onto it.
//
// url is the address users reach it at and there is no sane default: OpenCloud
// hands it to its own web client and to every OIDC redirect, so a wrong value
// serves a UI that cannot talk to its own backend. TLS is terminated in front of
// the pod (PROXY_TLS=false), which is what makes an ordinary HTTP exposure work —
// left at its default the proxy would answer TLS with a self-signed certificate.
//
// Single writer: the configuration, the users database and the file blobs all sit
// on ReadWriteOnce volumes, so one replica, recreated (never rolled) to keep two
// pods off them.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='opencloud',
  image=defaultImage,
  // The public address users reach this instance at, scheme included.
  url='https://opencloud.example.com',
  storageSize='50Gi',
  configSize='1Gi',
  storageClass=null,
  port=9200,
  // The Secret holding IDM_ADMIN_PASSWORD, read ONCE by the init step that creates
  // the first administrator. Changing it afterwards does not change the password:
  // by then it lives hashed in OpenCloud's own identity store.
  secretName='opencloud',
  env={},
  resources={ requests: { cpu: '500m', memory: '1Gi' }, limits: { memory: '4Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(port)
  + kurly.servicePort(port)
  + kurly.env({
    OC_URL: url,
    // Terminate TLS in front of the pod; without this the proxy answers HTTPS
    // with a certificate it generated for itself, which every exposure in kurly
    // would then have to be told to trust.
    PROXY_TLS: 'false',
    PROXY_HTTP_ADDR: '0.0.0.0:' + port,
    OC_CONFIG_DIR: '/etc/opencloud',
    OC_BASE_DATA_PATH: '/var/lib/opencloud',
  } + env)
  // The image declares USER 1000 and needs nothing root gives it — the only port
  // it binds is above 1024 — so the hardened posture stands; fsGroup is what makes
  // the volumes writable.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.store('/var/lib/opencloud', storageSize, storageClass=storageClass)
  // The configuration is a SEPARATE volume from the data, because `opencloud init`
  // writes the machine's service secrets and signing keys into it: they are what
  // every internal service authenticates with, so losing them while keeping the
  // blobs leaves an instance that cannot read its own files.
  + kurly.store('/etc/opencloud', configSize, storageClass=storageClass)
  + kurly.scratch('/tmp')
  // `opencloud server` refuses to start without that configuration, and the only
  // thing that writes one is `opencloud init` — which MINTS secrets, so it must run
  // exactly once. Rerunning it would issue new ones and orphan everything the old
  // ones signed, which is why the guard is a correctness condition and not a
  // speed-up. --insecure no keeps the generated config strict; the admin password
  // comes from the Secret, and init generates and prints one when the key is absent.
  + kurly.initContainer({
    name: 'init',
    image: image,
    command: [
      'sh',
      '-c',
      'test -f /etc/opencloud/opencloud.yaml || opencloud init --insecure no',
    ],
    env: [{ name: 'OC_CONFIG_DIR', value: '/etc/opencloud' }],
    envFrom: [{ secretRef: { name: secretName } }],
    volumeMounts: [{ name: 'etc-opencloud', mountPath: '/etc/opencloud' }],
  })
  // The proxy validates the Host header against OC_URL and answers a redirect to
  // it otherwise, so a probe naming a path would be judging the redirect rather
  // than the server. Probe by connection instead.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  // One process starts every internal service and provisions the demo-free default
  // spaces on the first boot, which takes minutes on a small node.
  + kurly.startupProbe({ tcpSocket: { port: 'http' }, failureThreshold: 60, periodSeconds: 5 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
