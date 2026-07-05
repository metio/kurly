// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// An internet-facing web frontend: Deployment, Service, and Ingress. The
// image must run as a non-root user — every kurly workload ships the Pod
// Security Standards `restricted` profile by default.
local kurly = import '../main.libsonnet';

kurly.list(
  kurly.web.new('storefront', 'docker.io/nginxinc/nginx-unprivileged:1.29')
  .withReplicas(3)
  .withHttpProbes('/')
  .withIngressClass('nginx')
  .withHost('shop.example.com')
)
