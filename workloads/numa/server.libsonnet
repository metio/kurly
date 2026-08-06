// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// numa — an ad-blocking DNS resolver in a single Rust binary: a forwarding or
// recursive resolver with DNSSEC validation, a blocklist, a DNS-over-TLS
// listener and an HTTP control plane. A plain composable kurly.http workload;
// its numa.toml is the only state it needs, rendered as a ConfigMap. Import it
// and render with kurly.list:
//
//   local numa = import 'github.com/metio/kurly/workloads/numa/server.libsonnet';
//   kurly.list(numa())
//
// DNS: numa answers on :53 (TCP and UDP) and DoT on :853, published on the
// Service beside the API port; route them (usually a LoadBalancer) so clients
// can point their resolver at it.
//
// API: the dashboard, the REST control plane and /metrics serve on :5380 —
// compose an exposure onto it if you want them. It is authenticated (HTTP Basic
// against the API token), so both probes check the CONNECTION: an HTTP probe
// gets a 401 and would restart a resolver answering queries perfectly well.
// numa mints a token on every start and cannot persist it here, so
// NUMA_API_TOKEN pins one from the Secret named by secretName — without it the
// token changes on every restart and every client is locked out.
//
// CONFIG: numa reads the config PATH FROM ITS ARGUMENT (`numa <config-path>`)
// rather than from a flag; the image's own default lives under $HOME, which is
// unset here, so the path is stated explicitly. `upstream` and `blocking` are
// the two tables most deployments change; `settings` merges over the whole
// document for numa's other tables (zones, forwarding, client_policy, dnssec).
// Note DNSSEC validation requires upstream.mode = 'recursive' — a forwarder
// validates nothing itself.
//
// The .numa HTTPS proxy (:80/:443) is OFF: it serves LAN service discovery
// behind a certificate authority numa generates itself and every client device
// must then trust, which is not what a cluster ingress is for.
//
// Stateless: numa keeps no database, so no PersistentVolume and any replica
// count is safe — its data directory (the DoT certificate, the API token, the
// blocklist downloads) is a scratch volume, so a restarted pod regenerates the
// self-signed DoT certificate. Point `dot.cert_path`/`key_path` at a mounted
// certificate through `settings` where clients pin it.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './server.image', '\n');

function(
  name='numa',
  image=defaultImage,
  replicas=1,
  // The upstream resolvers queries are forwarded to. Set mode='recursive' to
  // resolve from the root servers instead, which is also what DNSSEC needs.
  upstream={ address: ['9.9.9.9', '1.1.1.1'] },
  // Ad blocking, on by default: the lists numa ships with unless named here.
  blocking={ enabled: true },
  // Merged over the whole numa.toml, table by table: a table named here
  // REPLACES the one below rather than merging into it.
  settings={},
  secretName='numa',
  resources={ requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  labels={},
  annotations={},
)
  local numaToml = {
    server: {
      // The bind address carries the DNS port; api_bind_addr defaults to
      // loopback, where neither the probe nor the Service reaches it.
      bind_addr: '0.0.0.0:53',
      api_bind_addr: '0.0.0.0',
      api_port: 5380,
      data_dir: '/var/lib/numa',
    },
    upstream: upstream,
    blocking: blocking,
    dot: { enabled: true, port: 853, bind_addr: '0.0.0.0' },
    proxy: { enabled: false },
  } + settings;

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(5380)
  + kurly.servicePort(5380)
  + kurly.extraPort('dns-tcp', 53)
  + kurly.extraPort('dns-udp', 53, protocol='UDP')
  + kurly.extraPort('dot', 853)
  + kurly.args(['/etc/numa/numa.toml'])
  + kurly.config({ 'numa.toml': std.manifestTomlEx(numaToml, '') }, mountPath='/etc/numa')
  // NUMA_API_TOKEN pins the control-plane token across restarts.
  + kurly.envFromSecret(secretName)
  // The image runs as root and sets no user of its own; a numeric uid keeps the
  // restricted posture, and the one privilege a DNS server holds — binding the
  // privileged ports 53 and 853 — is granted by name rather than by keeping
  // every default capability.
  + kurly.runAs(65532, gid=65532)
  + kurly.addCapabilities(['NET_BIND_SERVICE'])
  // The data directory holds the generated DoT certificate, the API token and
  // the downloaded blocklists; HOME points into it so the services registry
  // numa writes beside its config lands somewhere writable too.
  + kurly.scratch('/var/lib/numa')
  + kurly.env({ HOME: '/var/lib/numa' })
  // Both probes check the connection: the API answers 401 without the token.
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
