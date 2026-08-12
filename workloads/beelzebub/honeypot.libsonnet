// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// beelzebub — a low-code honeypot: it pretends to be services an attacker wants
// to find (SSH, HTTP, databases), records what they try, and answers convincingly
// enough to keep them going. A plain composable kurly.http workload: every
// service it impersonates is a YAML file, rendered here as a ConfigMap, and the
// events go to stdout or an external sink. Import it and render with kurly.list:
//
//   local beelzebub = import 'github.com/metio/kurly/workloads/beelzebub/honeypot.libsonnet';
//   kurly.list(beelzebub(services={
//     'http-80': { apiVersion: 'v1', protocol: 'http', address: ':8080', description: 'Apache 2.4' },
//   }))
//
// A HONEYPOT IS MEANT TO BE ATTACKED, WHICH MAKES IT THE ONE WORKLOAD IN A
// NAMESPACE YOU MUST ASSUME IS COMPROMISED. It runs with the hardened default —
// unprivileged, read-only root filesystem, no capabilities — and it belongs in a
// namespace of its own with a NetworkPolicy that lets it reach NOTHING inside the
// cluster. Beelzebub emulates its services rather than running the real ones, so
// a break-out is a break-out of a Go process, not of sshd; that is a reason for
// care, not for confidence.
//
// PORTS FOLLOW THE SERVICES. Each service names its own `address`, and the ports
// published on the Service are derived from those addresses — there is no list to
// keep in step by hand. The first service's port is the one probed. A service
// wanting a port below 1024 needs kurly.addCapabilities(['NET_BIND_SERVICE']), or
// better, an exposure that maps 22 to something unprivileged here.
//
// Stateless: events leave over stdout, so no volume, and any replica count is
// legal — though each replica sees only the attacks that reach it.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './honeypot.image', '\n');

// ':8080' and '0.0.0.0:8080' both mean 8080; the port is whatever follows the
// last colon.
local portOf(address) =
  local parts = std.split(address, ':');
  std.parseInt(parts[std.length(parts) - 1]);

function(
  name='beelzebub',
  image=defaultImage,
  replicas=1,
  // One entry per impersonated service, keyed by file name; each is a Beelzebub
  // service definition, passed through verbatim.
  services={
    'http-8080': {
      apiVersion: 'v1',
      protocol: 'http',
      address: ':8080',
      description: 'A generic HTTP server',
      commands: [{ regex: '.*', handler: '<html><body>It works</body></html>', statusCode: 200 }],
    },
  },
  // Beelzebub's own global settings, as the BEELZEBUB_* environment overrides:
  // BEELZEBUB_LOGGING_DEBUG, BEELZEBUB_PROMETHEUS_PORT, BEELZEBUB_RABBITMQ_URI
  // and the rest.
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  local names = std.objectFields(services);
  assert std.length(names) > 0 : 'beelzebub: at least one service is needed — a honeypot listening on nothing catches nothing';
  local ports = [{ name: n, port: portOf(services[n].address) } for n in names];

  kurly.http(name, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(ports[0].port)
  + kurly.servicePort(ports[0].port)
  + kurly.env(env)
  // Every service after the first, published beside it.
  + std.foldl(
    function(acc, p) acc + kurly.extraPort(p.name, p.port),
    ports[1:],
    {}
  )
  // The image is FROM scratch with a single static binary and no user of its own,
  // so any unprivileged uid serves.
  + kurly.runAs(65534, gid=65534)
  // ONE ConfigMap, holding the services and nothing else. Beelzebub also reads a
  // core configuration file, and a missing one is not an error — it falls back to
  // its defaults and the BEELZEBUB_* environment overrides, which is what `env`
  // is for. A second ConfigMap is not an option: kurly gives a workload one, and
  // a second kurly.config() would silently replace the first.
  + kurly.config(
    { [n + '.yaml']: std.manifestYamlDoc(services[n], quote_keys=false) for n in names },
    mountPath='/configurations/services'
  )
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
