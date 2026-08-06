// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// lancache — a LanCache monolithic server (a caching proxy for game downloads on
// a local network: the first machine to download a title pulls it from the
// internet, every machine after it reads the same bytes off the local disk). A
// plain composable kurly.http workload on the official image, keeping its cache
// and logs on PersistentVolumes. Import it and render with kurly.list:
//
//   local lancache = import 'github.com/metio/kurly/workloads/lancache/server.libsonnet';
//   kurly.list(lancache())
//
// Serves the cache on :80 — compose an exposure onto it, though in practice this
// is routed at layer 4 (a LoadBalancer) rather than through an HTTP router: the
// clients never ask for it by name, they are pointed at it by DNS.
//
// DNS IS THE HALF THAT IS NOT HERE. A cache only sees a download if the client
// resolves the content-delivery hostname to this pod's address, which is a
// resolver's job — the monolithic image caches, it does not answer DNS. Run
// something that does (blocky, pihole, dnsmasq) with the uklans cache-domains
// list pointed at this Service's address, or the workload runs perfectly and
// caches nothing. The 'https' port (:443) is the SNI proxy: it does not
// intercept TLS, it forwards it, so a domain served over HTTPS passes through
// uncached and keeps working.
//
// EGRESS: the entrypoint refreshes the uklans cache-domains list over git and
// every miss is fetched from the upstream CDN, so this pod needs egress to the
// internet — a NetworkPolicy written from the shape of the manifest blocks the
// very traffic the workload exists to make.
//
// SIZING: cacheDiskSize is what nginx believes it may fill, and it is a SEPARATE
// number from the volume, in nginx's own units. Leave headroom — the image's own
// default is 1000g, which on a smaller volume fills the disk before the cache
// manager ever starts evicting.
//
// The image is a supervisord/nginx stack that generates its configuration at
// boot and drops its workers to www-data, so it runs as root with a writable
// root filesystem and the capabilities that hand-off needs.
//
// Single writer: one cache directory on a ReadWriteOnce volume, so one replica,
// recreated (never rolled).
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='lancache',
  image=defaultImage,
  // The cache itself. Real deployments run this in the terabytes; the default is
  // sized to be startable, not to be useful.
  cacheSize='50Gi',
  // What nginx is told it may fill, in nginx's units, and the free floor it
  // stops at. Both are smaller than the volume on purpose.
  cacheDiskSize='45g',
  minFreeDisk='5g',
  // How long a cached object may live, and the slice granularity the cache is
  // written in. Upstream defaults.
  cacheMaxAge='3560d',
  cacheSliceSize='1m',
  logsSize='2Gi',
  storageClass=null,
  // Where nginx sends the requests it cannot answer from cache.
  upstreamDns='8.8.8.8 8.8.4.4',
  timezone='UTC',
  env={},
  resources={ requests: { cpu: '200m', memory: '512Mi' }, limits: { memory: '2Gi' } },
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.port(80)
  + kurly.servicePort(80)
  // The SNI proxy, which forwards TLS rather than caching it, and the metrics
  // vhost the image serves on :8080.
  + kurly.extraPort('https', 443)
  + kurly.extraPort('metrics', 8080)
  + kurly.env({
    UPSTREAM_DNS: upstreamDns,
    CACHE_DISK_SIZE: cacheDiskSize,
    MIN_FREE_DISK: minFreeDisk,
    CACHE_MAX_AGE: cacheMaxAge,
    CACHE_SLICE_SIZE: cacheSliceSize,
    TZ: timezone,
  } + env)
  // The entrypoint generates the nginx configuration under /etc/nginx at every
  // boot and nginx's master process starts as root to bind :80 and :443 before
  // dropping its workers to www-data — a hand-off that needs the setuid
  // capabilities and the escalation the restricted profile otherwise denies.
  + kurly.rootUser()
  + kurly.allowPrivilegeEscalation()
  + kurly.keepCapabilities()
  + kurly.writableRootFilesystem()
  + kurly.store('/data/cache', cacheSize, storageClass=storageClass)
  + kurly.store('/data/logs', logsSize, storageClass=storageClass)
  + kurly.scratch('/tmp')
  // /lancache-heartbeat is the image's own health endpoint, answered by nginx
  // once the generated configuration is loaded.
  + kurly.readinessProbe({ httpGet: { path: '/lancache-heartbeat', port: 'http' } })
  + kurly.livenessProbe({ httpGet: { path: '/lancache-heartbeat', port: 'http' } })
  // First boot clones the uklans cache-domains list and writes a vhost per
  // cached service before nginx serves anything, which takes minutes on a slow
  // link — a startup probe waits for that instead of a liveness probe killing it
  // half way through.
  + kurly.startupProbe({ httpGet: { path: '/lancache-heartbeat', port: 'http' }, periodSeconds: 10, failureThreshold: 60 })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
