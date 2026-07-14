// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// A workload that brings its own listener to a shared Gateway: Deployment,
// Service, a ListenerSet attached to the platform team's Gateway (which must
// allow ListenerSets via spec.allowedListeners), and an HTTPRoute through it.
local kurly = import '../main.libsonnet';

kurly.list(
  kurly.http('storefront', 'docker.io/nginxinc/nginx-unprivileged:1.29')
  + kurly.replicas(3)
  + kurly.probes('/')
  + kurly.expose.ownListenerSet('shop.example.com', 'shared-gateway', gatewayNamespace='infrastructure')
)
