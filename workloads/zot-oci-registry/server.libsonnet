// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// zot-oci-registry — a zot server (a vendor-neutral, OCI-native container image registry:
// it stores images in the OCI image layout on disk rather than in a registry-specific one).
// A plain composable kurly.http workload on the official image; its stored images live on a
// PersistentVolume. Import it and render with kurly.list:
//
//   local zot = import 'github.com/metio/kurly/workloads/zot-oci-registry/server.libsonnet';
//   kurly.list(zot())
//
// Serves the registry API on :5000 — usually reached in-cluster (zot-oci-registry:5000);
// compose an exposure onto it only if it is pulled from outside.
//
// CONFIGURATION IS A FILE, NOT ENVIRONMENT: zot reads one JSON document, so the whole config
// is rendered into a ConfigMap mounted at /etc/zot and `config` merges into it verbatim —
// that is the escape hatch for authentication, access control, sync and storage drivers,
// none of which kurly models (zot's schema is large and moves).
//
// AUTH & TLS: with no `config` of your own this registry is unauthenticated and plaintext.
// Give it htpasswd or OIDC through `config.http.auth` and TLS in front of it, or keep it
// inside the cluster.
//
// THE CVE SCANNER IS OFF BY DEFAULT. The image's own config enables it, and it then downloads
// and holds a vulnerability database — hundreds of megabytes of disk and well over the memory
// this workload requests. Turn it on with `cve=true` AND raise the limits, or leave it off and
// scan images where you build them.
//
// Single writer: the image store lives on a ReadWriteOnce volume, so one replica, recreated
// (never rolled) — two zot processes writing one OCI layout is not a thing either of them
// arbitrates.
local kurly = import 'github.com/metio/kurly/main.libsonnet';
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');
function(
  name='zot-oci-registry',
  image=defaultImage,
  storageSize='50Gi',
  storageClass=null,
  logLevel='info',
  ui=true,
  cve=false,
  config={},
  env={},
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local baseConfig = {
    storage: { rootDirectory: '/var/lib/registry' },
    // docker2s2 keeps `docker push` working against a registry that stores the OCI layout.
    http: { address: '0.0.0.0', port: '5000', compat: ['docker2s2'] },
    log: { level: logLevel },
    extensions: {
      // The UI is served by the search extension's data, so it cannot be enabled alone.
      search: { enable: ui || cve } + (if cve then { cve: { updateInterval: '2h' } } else {}),
      ui: { enable: ui },
      mgmt: { enable: ui },
    },
  };
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(5000)
  + kurly.servicePort(5000)
  + kurly.env(env)
  // The image declares USER 0 but the binary needs nothing root gives it; the volume comes
  // with fsGroup, so it runs unprivileged with the hardened default intact.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  + kurly.config({ 'config.json': std.manifestJsonEx(baseConfig + config, '  ') }, mountPath='/etc/zot')
  + kurly.store('/var/lib/registry', storageSize, storageClass=storageClass)
  // /v2/ is the registry API root and answers 200 unauthenticated only while no auth is
  // configured — probe by connection instead once you configure one, or the probe's 401
  // kills the pod for being correctly secured.
  + kurly.readinessProbe({ httpGet: { path: '/v2/', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/v2/', port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
