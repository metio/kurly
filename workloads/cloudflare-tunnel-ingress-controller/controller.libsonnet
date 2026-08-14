// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// cloudflare-tunnel-ingress-controller — publishes Ingress objects through a
// Cloudflare Tunnel instead of a load balancer: the controller watches Ingresses
// of its class, programs the tunnel's routes and the DNS records to match, and
// the tunnel dials OUT to Cloudflare, so nothing in the cluster has to be
// reachable from the internet. A composable kurly.worker workload — it serves no
// traffic of its own, so it renders no Service — holding no state.
// Import it and render with kurly.list:
//
//   local ctrl = import 'github.com/metio/kurly/workloads/cloudflare-tunnel-ingress-controller/controller.libsonnet';
//   kurly.list(ctrl(namespace='cloudflare-tunnel', accountId='…', tunnelName='k8s', secretName='cloudflare-tunnel'))
//
// IT WATCHES INGRESSES CLUSTER-WIDE, WHICH IS THE CLUSTER-WIDE GRANT. An Ingress
// is a namespaced object in every namespace, so reading them is a ClusterRole,
// and the controller also writes their status. It creates no CustomResource and
// owns none: the interface is the standard Ingress with this controller's class.
//
// THE API TOKEN CAN EDIT YOUR DNS. The token needs Zone:Read, DNS:Edit and
// Cloudflare Tunnel:Edit on the account, so whatever holds it can repoint the
// zone. It comes from a Secret as CLOUDFLARE_API_TOKEN and is passed to the flag
// through $(CLOUDFLARE_API_TOKEN), which Kubernetes expands from the container's
// own environment — the token is never written into the manifest.
//
// Stateless: the tunnel's configuration lives in Cloudflare's account, not here.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

// kurly's own packaging version, stamped as kurly.metio.wtf/version; the release
// pipeline overwrites version.txt with the calver. The application's version is
// app.kubernetes.io/version, which comes from the image tag.
local version = std.rstripChars(importstr './version.txt', '\n');
local defaultImage = std.rstripChars(importstr './controller.image', '\n');

function(
  name='cloudflare-tunnel-ingress-controller',
  image=defaultImage,
  // The namespace this is deployed into; the ClusterRoleBinding's subject needs
  // it, and one without a namespace grants nothing.
  namespace='cloudflare-tunnel',
  // The Cloudflare account the tunnel belongs to. THE CONTROLLER DOES NOT START
  // WITHOUT IT — empty renders a controller that exits on its first reconcile,
  // which is deliberate: an account id is a fact about the deployment and there
  // is no value to guess.
  accountId='',
  // The tunnel's name. The controller creates it when it does not exist.
  tunnelName='kubernetes',
  // The ingress class this controller answers for. An Ingress naming another
  // class is left to whoever owns that one.
  ingressClass='cloudflare-tunnel',
  controllerClass='strrl.dev/cloudflare-tunnel-ingress-controller',
  // A Secret carrying CLOUDFLARE_API_TOKEN.
  secretName='cloudflare-tunnel-ingress-controller',
  extraArgs=[],
  env={},
  resources={ requests: { cpu: '50m', memory: '64Mi' }, limits: { memory: '256Mi' } },
  labels={},
  annotations={},
)
  kurly.worker(name, image)
  + kurly.version(version)
  + kurly.replicas(1)
  + kurly.recreate()
  + kurly.command(['cloudflare-tunnel-ingress-controller'])
  + kurly.args([
    '--cloudflare-api-token=$(CLOUDFLARE_API_TOKEN)',
  ] + (if accountId != '' then ['--cloudflare-account-id=' + accountId] else []) + [
    '--cloudflare-tunnel-name=' + tunnelName,
    '--ingress-class=' + ingressClass,
    '--controller-class=' + controllerClass,
    '--namespace=' + namespace,
  ] + extraArgs)
  + kurly.env(env)
  + kurly.envFromSecret(secretName)
  // Ingresses in every namespace, and their status written back. Nothing else:
  // the controller creates no Kubernetes object of its own.
  + kurly.clusterRbac(
    [
      { apiGroups: ['networking.k8s.io'], resources: ['ingresses'], verbs: ['get', 'list', 'watch', 'update'] },
      { apiGroups: ['networking.k8s.io'], resources: ['ingresses/status'], verbs: ['get', 'update', 'patch'] },
      { apiGroups: ['networking.k8s.io'], resources: ['ingressclasses'], verbs: ['get', 'list', 'watch'] },
      { apiGroups: [''], resources: ['services', 'endpoints'], verbs: ['get', 'list', 'watch'] },
    ],
    namespace=namespace
  )
  + kurly.scratch('/tmp', '64Mi')
  + kurly.resources(requests=std.get(resources, 'requests', {}), limits=std.get(resources, 'limits', {}))
  + kurly.labels(labels)
  + kurly.annotations(annotations)
