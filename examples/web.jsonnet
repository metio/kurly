// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// An internet-facing web frontend via the Ingress API: Deployment, Service,
// and Ingress. The image must run as a non-root user — every kurly workload
// ships the Pod Security Standards `restricted` profile by default.
local kurly = import '../main.libsonnet';

kurly.list(
  kurly.http('storefront', 'docker.io/nginxinc/nginx-unprivileged:1.29')
  + kurly.replicas(3)
  + kurly.probes('/')
  + kurly.expose.ingress('shop.example.com', ingressClass='nginx')
)
