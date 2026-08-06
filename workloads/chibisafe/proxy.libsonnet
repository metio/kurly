// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// chibisafe-proxy — the Caddy edge that makes chibisafe one origin: it serves the
// uploaded files off the server's volume, forwards /api and /docs to the server,
// and hands everything else to the frontend. This is the stage you expose. One of
// the three chibisafe stages — see the server stage's header and the workload
// README for the whole picture.
//
//   local proxy = import 'github.com/metio/kurly/workloads/chibisafe/proxy.libsonnet';
//   kurly.list(proxy() + kurly.expose.ingress('files.example.com'))
//
// Serves on :8080.
//
// WHY IT EXISTS: the backend registers its static file route only outside
// production, so in a released image NOTHING serves the uploads — the very links
// chibisafe hands out. Upstream's compose file puts Caddy in front for exactly
// that reason, and this stage is that Caddy, with the upstream names replaced by
// the stage names so a namespace can run two copies.
//
// STORAGE: it serves the uploads straight off the server's claim and therefore
// mounts it read-only. With the server's ReadWriteOnce default both pods must
// schedule onto the same node; give the server a ReadWriteMany class to spread
// them. There is no serving without that mount, so it is not optional.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './proxy.image', '\n');

function(
  namePrefix='chibisafe',
  name=null,
  image=defaultImage,
  replicas=2,
  serverHost=null,
  serverPort=8000,
  frontendHost=null,
  frontendPort=8001,
  // The server's uploads claim, mounted read-only at uploadsPath; null derives
  // the name the server stage's first store renders.
  storageClaim=null,
  uploadsPath='/app/uploads',
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '128Mi' } },
  labels={},
  annotations={},
)
  local resolvedName = if name != null then name else namePrefix + '-proxy';
  local server = (if serverHost != null then serverHost else namePrefix + '-server') + ':' + serverPort;
  local frontend = (if frontendHost != null then frontendHost else namePrefix + '-frontend') + ':' + frontendPort;
  local claim = if storageClaim != null then storageClaim else namePrefix + '-server-store';

  // Upstream's own Caddyfile, restated over the stage's names. The site address
  // is a bare port, so Caddy serves plain HTTP and never asks for a certificate:
  // TLS belongs to the exposure composed onto this stage.
  local caddyfile = |||
    {
    	servers {
    		trusted_proxies static private_ranges
    		client_ip_headers X-Forwarded-For X-Real-IP
    	}
    }

    :8080 {
    	route {
    		file_server * {
    			root %(uploads)s
    			pass_thru
    		}

    		@api path /api/*
    		reverse_proxy @api http://%(server)s {
    			header_up Host {http.reverse_proxy.upstream.hostport}
    			header_up X-Real-IP {http.request.header.X-Real-IP}
    		}

    		@docs path /docs*
    		reverse_proxy @docs http://%(server)s {
    			header_up Host {http.reverse_proxy.upstream.hostport}
    			header_up X-Real-IP {http.request.header.X-Real-IP}
    		}

    		reverse_proxy http://%(frontend)s {
    			header_up Host {http.reverse_proxy.upstream.hostport}
    			header_up X-Real-IP {http.request.header.X-Real-IP}
    		}
    	}
    }
  ||| % {
    uploads: uploadsPath,
    server: server,
    frontend: frontend,
  };

  local storage = {
    deployment+: { spec+: { template+: { spec+: {
      volumes+: [{ name: 'uploads', persistentVolumeClaim: { claimName: claim, readOnly: true } }],
      containers: [
        container { volumeMounts+: [{ name: 'uploads', mountPath: uploadsPath, readOnly: true }] }
        for container in super.containers
      ],
    } } } },
  };

  kurly.http(resolvedName, image)
  + kurly.version(version)
  + kurly.replicas(replicas)
  + kurly.port(8080)
  + kurly.servicePort(8080)
  // The image reads /etc/caddy/Caddyfile and ships nothing else in that directory.
  + kurly.config({ Caddyfile: caddyfile }, mountPath='/etc/caddy')
  // The admin API autosaves the running config under XDG_CONFIG_HOME, which the
  // image sets to /config. Pointing it into the scratch below avoids a second
  // volume at /config, whose generated name would collide with the ConfigMap's.
  + kurly.env({ XDG_CONFIG_HOME: '/data/config' })
  // The image declares root and the entrypoint drops nothing, so the user is
  // pinned here. The uploads are read, never written.
  + kurly.runAs(1000, gid=1000, fsGroup=1000)
  // The binary carries the file capability cap_net_bind_service, and a file with
  // permitted capabilities cannot be exec'd at all once the bounding set drops
  // them: the kernel refuses with `exec /usr/bin/caddy: operation not permitted`,
  // which reads as a broken image rather than a dropped capability.
  + kurly.addCapabilities(['NET_BIND_SERVICE'])
  // XDG_DATA_HOME: Caddy's own state and the autosaved config.
  + kurly.scratch('/data')
  + kurly.readinessProbe({ tcpSocket: { port: 'http' } })
  + kurly.livenessProbe({ tcpSocket: { port: 'http' } })
  + kurly.resources(
    requests=std.get(resources, 'requests', {}),
    limits=std.get(resources, 'limits', {}),
  )
  + kurly.labels(labels)
  + kurly.annotations(annotations)
  + storage
