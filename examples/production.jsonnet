// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// A production deployment in one call: kurly.production bundles the standard
// concerns a self-service portal repeats for every tenant — exposure onto a
// shared Gateway, a cert-manager Certificate for the host, a NetworkPolicy
// allow-list (deny-by-default), a resource tier, replicas, and a priority class —
// onto a composed app. The portal writes this, not the assembled recipe.
local kurly = import '../main.libsonnet';

kurly.list(kurly.production(
  kurly.http('storefront', 'docker.io/nginxinc/nginx-unprivileged:1.31')
  + kurly.port(8080),
  host='storefront.tenant1.example.com',
  gateway='shared',
  gatewayNamespace='infrastructure',
  sectionName='https',
  tls='storefront-tenant1-tls',
  issuer='letsencrypt-prod',
  resourceTier='small',
  replicas=2,
  priorityClassName='standard',
  // Only the shared gateway's pods may reach the workload; it may reach its
  // database and the cluster DNS.
  allowFrom=[{ pods: { 'app.kubernetes.io/name': 'envoy' }, namespace: 'infrastructure', ports: [8080] }],
  allowTo=[
    { pods: { 'app.kubernetes.io/name': 'postgres' }, namespace: 'databases', ports: [5432] },
    { namespace: 'kube-system', ports: [{ port: 53, protocol: 'UDP' }] },
  ],
))
