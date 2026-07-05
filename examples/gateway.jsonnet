// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// An internet-facing workload via the Gateway API: Deployment, Service, and
// an HTTPRoute attached to a Gateway the platform team already runs — the
// usual Gateway API setup. expose.ownGateway and expose.ownListenerSet cover
// clusters where the workload has to bring its own listener instead.
local kurly = import '../main.libsonnet';

kurly.list(
  kurly.http.new('storefront', 'docker.io/nginxinc/nginx-unprivileged:1.29')
  .withReplicas(3)
  .withHttpProbes('/')
  + kurly.expose.gateway('shop.example.com', 'shared-gateway', gatewayNamespace='infrastructure')
)
