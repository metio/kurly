// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// traefik — an edge router that discovers its own configuration from the cluster:
// it watches Ingress, IngressRoute and Gateway API objects and routes traffic to
// the Services behind them, obtaining certificates as it goes. A composable
// kurly.http workload. Import it and render with kurly.list:
//
//   local traefik = import 'github.com/metio/kurly/workloads/traefik/ingress.libsonnet';
//   kurly.list(traefik(namespace='traefik'))
//
// Serves :8000 (web) and :8443 (websecure), with the dashboard and metrics on
// :9000 — compose an exposure onto the entry points, usually a LoadBalancer
// Service.
//
// UNPRIVILEGED PORTS, DELIBERATELY. Traefik's own image listens on :80 and :443,
// which a container without NET_BIND_SERVICE cannot bind. Rather than grant that
// capability, the entry points here are 8000 and 8443 and the Service maps 80 and
// 443 onto them — the arrangement that keeps the hardened posture and the one a
// LoadBalancer in front makes invisible to clients.
//
// IT READS INGRESS OBJECTS ACROSS THE CLUSTER, which is what an edge router does
// and why the grant is cluster-wide. `namespace` is required: a ClusterRoleBinding
// naming no namespace grants nothing. The rules cover the Kubernetes Ingress
// provider and the Gateway API; Traefik's own CRDs (IngressRoute, Middleware and
// the rest) are NOT granted here, because a cluster that has not installed them
// would be given permissions on kinds that do not exist — compose extraRules when
// they are.
//
// THE DASHBOARD IS NOT EXPOSED and `api.insecure` is off. Traefik's dashboard has
// no authentication of its own, so publishing it publishes the routing table of
// the whole cluster.
//
// CERTIFICATES: `acmeEmail` turns on a Let's Encrypt resolver storing its account
// and certificates on the volume. Without it Traefik serves its own self-signed
// certificate, which is fine behind something that already terminates TLS.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './ingress.image', '\n');

function(
  name='traefik',
  image=defaultImage,
  // The namespace this is deployed into; the ClusterRoleBinding's subject needs
  // it, and one without a namespace grants nothing.
  namespace='traefik',
  replicas=2,
  // An email address turns on the Let's Encrypt resolver; the account key and the
  // certificates live on the volume.
  acmeEmail=null,
  storageSize='1Gi',
  storageClass=null,
  // Rules ADDED to the grant — where Traefik's own CRDs go on a cluster that has
  // installed them.
  extraRules=[],
  // Appended to Traefik's own flags.
  extraArgs=[],
  resources={ requests: { cpu: '100m', memory: '128Mi' }, limits: { memory: '512Mi' } },
  env={},
  labels={},
  annotations={},
)
  kurly.http(name, image)
  + kurly.version(version)
  // One replica when ACME is on: the certificate store is a file on a
  // ReadWriteOnce volume, and two routers racing for the same account produce
  // rate-limit failures rather than certificates. Traefik's distributed answer is
  // a certificate resolver backed by something shared, which is a different
  // arrangement than this stage.
  + kurly.replicas(if acmeEmail != null then 1 else replicas)
  + (if acmeEmail != null then kurly.recreate() else {})
  + kurly.port(8000)
  + kurly.servicePort(80)
  + kurly.extraPort('websecure', 8443, servicePort=443)
  // The dashboard and the Prometheus metrics, on the pod only.
  + kurly.extraPort('traefik', 9000, expose=false)
  + kurly.env(env)
  + kurly.args(
    [
      '--entrypoints.web.address=:8000',
      '--entrypoints.websecure.address=:8443',
      '--entrypoints.traefik.address=:9000',
      '--ping=true',
      '--ping.entrypoint=traefik',
      '--metrics.prometheus=true',
      '--providers.kubernetesingress=true',
      '--providers.kubernetesgateway=true',
    ]
    + (if acmeEmail != null then [
         '--certificatesresolvers.letsencrypt.acme.email=' + acmeEmail,
         '--certificatesresolvers.letsencrypt.acme.storage=/data/acme.json',
         '--certificatesresolvers.letsencrypt.acme.tlschallenge=true',
       ] else [])
    + extraArgs
  )
  // Watching what it routes to. Traefik's own CRDs are deliberately absent — see
  // the header.
  + kurly.clusterRbac(
    [
      { apiGroups: [''], resources: ['services', 'endpoints', 'secrets'], verbs: ['get', 'list', 'watch'] },
      { apiGroups: ['discovery.k8s.io'], resources: ['endpointslices'], verbs: ['list', 'watch'] },
      { apiGroups: ['networking.k8s.io'], resources: ['ingresses', 'ingressclasses'], verbs: ['get', 'list', 'watch'] },
      { apiGroups: ['networking.k8s.io'], resources: ['ingresses/status'], verbs: ['update'] },
      { apiGroups: ['gateway.networking.k8s.io'], resources: ['gatewayclasses', 'gateways', 'httproutes', 'grpcroutes', 'referencegrants', 'tcproutes', 'tlsroutes'], verbs: ['get', 'list', 'watch'] },
      { apiGroups: ['gateway.networking.k8s.io'], resources: ['gatewayclasses/status', 'gateways/status', 'httproutes/status', 'grpcroutes/status', 'tcproutes/status', 'tlsroutes/status'], verbs: ['update'] },
    ] + extraRules,
    namespace=namespace
  )
  // The image runs as root and needs nothing that root gives; the ACME store is
  // made writable by fsGroup.
  + kurly.runAs(65532, gid=65532, fsGroup=65532)
  + kurly.store('/data', storageSize, storageClass=storageClass)
  + kurly.scratch('/tmp', '64Mi')
  + kurly.readinessProbe({ httpGet: { path: '/ping', port: 'traefik' } })
  + kurly.livenessProbe({ httpGet: { path: '/ping', port: 'traefik' } })
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
