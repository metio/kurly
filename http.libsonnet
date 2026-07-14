// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// http: an HTTP workload — a Deployment (2 replicas) and a ClusterIP Service.
// In-cluster consumers reach it through the Service DNS name; to accept
// traffic from outside the cluster, compose an exposure feature on top:
//
//   kurly.http('shop', image) + kurly.expose.gateway('shop.example.com', 'shared')
local base = import './base.libsonnet';

function(name, image)
  base.core(name, image)
  + base.deployment
  + base.service
  + {
    config+:: {
      port: 8080,
      replicas: 2,
    },
  }
