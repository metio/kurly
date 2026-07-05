// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// api: an HTTP workload for in-cluster consumers — a Deployment (2 replicas)
// and a ClusterIP Service, no Ingress. Reach it through the Service DNS name.
local base = import './base.libsonnet';

{
  new(name, image)::
    base.core(name, image)
    + base.deployment
    + base.service
    + {
      config+:: {
        port: 8080,
        replicas: 2,
      },
    },
}
