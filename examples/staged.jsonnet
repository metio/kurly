// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// One workload, declared once, layered per rollout stage: dev runs a single
// unexposed replica, production runs three behind the shared Gateway. Renders
// a map of stage name -> kind: List — the shape the workload artifact
// pipeline packs into one OCI layer per stage, which a stageset-controller
// stage selects via its OCIRepository layerSelector.
local kurly = import '../main.libsonnet';

local shop = kurly.http.new('shop', 'docker.io/nginxinc/nginx-unprivileged:1.29')
             .withHttpProbes('/');

kurly.stageLists(shop, {
  dev: {
    config+:: { replicas: 1 },
  },
  production: {
    config+:: {
      replicas: 3,
      resources+: { limits: { memory: '256Mi' } },
    },
  } + kurly.expose.gateway('shop.example.com', 'shared-gateway', gatewayNamespace='infrastructure'),
})
