// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// harbor/registry — the OCI registry Harbor puts its API in front of: the
// upstream distribution server on :5000 plus registryctl, the small controller
// core drives for garbage collection and blob deletion, on :8080. The two share
// the image data, so registryctl runs as a SIDECAR in the same pod rather than a
// stage of its own — a second pod could not mount the ReadWriteOnce volume.
//
//   local registry = import 'github.com/metio/kurly/workloads/harbor/registry.libsonnet';
//   kurly.list([registry(), …])
//
// Nothing outside the cluster talks to this stage: clients reach the registry
// through core, which mints the bearer token they present here. Do NOT compose an
// exposure onto it.
//
// SECRETS: the same Secret the other stages read. REGISTRY_HTTP_SECRET signs the
// upload state a client carries between requests (every replica must agree on it,
// or a resumed layer upload fails), and REGISTRY_HTPASSWD is the bcrypt htpasswd
// line for the basic-auth user core authenticates with — the same username and
// password as the core stage's registryUser / REGISTRY_CREDENTIAL_PASSWORD.
//
// Images land on a PersistentVolume by default; point `storage` at an object
// store instead by passing the distribution storage stanza verbatim, which is
// what a registry of any size wants. One volume, one writer: one replica,
// recreated (never rolled) so two pods never contend for the ReadWriteOnce
// volume.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './registry.image', '\n');

function(
  name='harbor-registry',
  image=defaultImage,
  // registryctl ships as its own image, released in lockstep with the registry.
  controllerImage='docker.io/goharbor/harbor-registryctl:v2.15.0@sha256:463172f71d3a1e8d4f9e3b4e687a447f41fbc3126316d8c150dba04a903bbc47',
  redisHost='harbor-cache',
  redisPort='6379',
  secretName='harbor',
  storageSize='50Gi',
  storageClass=null,
  // The distribution `storage` stanza, passed through verbatim. The default is
  // the PersistentVolume this stage claims; an s3/azure/gcs stanza here replaces
  // it, and then storageSize buys nothing.
  storage=null,
  logLevel='info',
  resources={ requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } },
  controllerResources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
  podLabels={},
  podAnnotations={},
)
  local onPvc = storage == null;
  local configYml = std.manifestYamlDoc({
    version: '0.1',
    log: { level: logLevel, fields: { service: 'registry' } },
    storage: (if onPvc then { filesystem: { rootdirectory: '/storage' } } else storage) + {
      cache: { layerinfo: 'redis' },
      maintenance: { uploadpurging: { enabled: false } },
      // Harbor deletes manifests through this API; without it a garbage
      // collection run reclaims nothing.
      delete: { enabled: true },
      redirect: { disable: true },
    },
    redis: {
      addr: '%s:%s' % [redisHost, redisPort],
      db: 2,
      readtimeout: '10s',
      writetimeout: '10s',
      dialtimeout: '10s',
      pool: { maxidle: 100, maxactive: 500, idletimeout: '60s' },
    },
    http: {
      addr: ':5000',
      relativeurls: false,
      debug: { addr: 'localhost:5001' },
    },
    auth: { htpasswd: { realm: 'harbor-registry-basic-realm', path: '/etc/registry/passwd' } },
    validation: { disabled: true },
  }) + '\n';
  local ctlConfigYml = std.manifestYamlDoc({
    protocol: 'http',
    port: 8080,
    log_level: logLevel,
    registry_config: '/etc/registry/config.yml',
  }) + '\n';

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.port(5000)
  + kurly.servicePort(5000)
  // registryctl answers on its own port, published on the same Service because
  // core addresses it as REGISTRY_CONTROLLER_URL.
  + kurly.extraPort('controller', 8080)
  + kurly.envFromSecret(secretName)
  + kurly.runAs(10000, gid=10000, fsGroup=10000)
  + kurly.config({ 'config.yml': configYml, 'ctl-config.yml': ctlConfigYml }, mountPath='/etc/registry', subPath=true)
  + kurly.secretMount(secretName, '/etc/registry/passwd', subPath='REGISTRY_HTPASSWD')
  + (if onPvc then kurly.store('/storage', storageSize, storageClass=storageClass) + kurly.recreate() else kurly.scratch('/storage', '1Gi'))
  + kurly.scratch('/tmp', '128Mi')
  // Every Harbor image starts by copying a CA bundle into /home/harbor, beside
  // its own binaries and entrypoint scripts, so the root filesystem has to be
  // writable: an emptyDir over that one path would shadow the install tree and
  // leave the container nothing to run.
  + kurly.writableRootFilesystem()
  + kurly.sidecar({
    name: 'registryctl',
    image: controllerImage,
    ports: [{ containerPort: 8080, name: 'controller', protocol: 'TCP' }],
    envFrom: [{ secretRef: { name: secretName } }],
    volumeMounts: [
      // The controller reads the registry's own configuration and rewrites its
      // data, so it mounts both from the volumes the main container declares:
      // 'config' is the ConfigMap, 'store' the first store's claim.
      { name: 'config', mountPath: '/etc/registry/config.yml', subPath: 'config.yml', readOnly: true },
      { name: 'config', mountPath: '/etc/registryctl/config.yml', subPath: 'ctl-config.yml', readOnly: true },
      { name: (if onPvc then 'store' else 'storage'), mountPath: '/storage' },
    ],
    readinessProbe: { httpGet: { path: '/api/health', port: 8080 } },
    livenessProbe: { httpGet: { path: '/api/health', port: 8080 }, initialDelaySeconds: 20, periodSeconds: 20 },
    resources: controllerResources,
  })
  + kurly.readinessProbe({ tcpSocket: { port: 'http' }, periodSeconds: 10 })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' }, initialDelaySeconds: 20, periodSeconds: 20 })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + kurly.podLabels(podLabels)
  + kurly.podAnnotations(podAnnotations)
