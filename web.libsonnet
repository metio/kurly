// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// web: an HTTP workload reachable from outside the cluster — a Deployment
// (2 replicas), a ClusterIP Service, and (once withHost is called) an Ingress.
local base = import './base.libsonnet';
local k = import './k.libsonnet';

{
  new(name, image)::
    base.core(name, image)
    + base.deployment
    + base.service
    + {
      config+:: {
        port: 8080,
        replicas: 2,
        ingressClassName: null,
      },

      withIngressClass(ingressClassName):: self + { config+:: { ingressClassName: ingressClassName } },

      withHost(host):: self + {
        config+:: { host: host },

        ingress:
          local cfg = self.config;
          k.networking.v1.ingress.new(cfg.name)
          + k.networking.v1.ingress.metadata.withLabels(self.labels)
          + (
            if cfg.ingressClassName == null
            then {}
            else k.networking.v1.ingress.spec.withIngressClassName(cfg.ingressClassName)
          )
          + k.networking.v1.ingress.spec.withRules([{
            host: cfg.host,
            http: {
              paths: [{
                path: '/',
                pathType: 'Prefix',
                backend: {
                  service: {
                    name: cfg.name,
                    port: { name: 'http' },
                  },
                },
              }],
            },
          }]),
      },
    },
}
