// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// A per-node agent: a DaemonSet. Node agents often need host-level access —
// this one loads kernel state, so it opts back onto the host user namespace;
// everything else in the restricted profile stays on.
local kurly = import '../main.libsonnet';

kurly.list(
  kurly.daemon('node-agent', 'ghcr.io/example/node-agent:0.9.2')
  + kurly.serviceAccount('node-agent')
  + kurly.hostUsers()
  + kurly.resources(requests={ cpu: '50m', memory: '64Mi' })
)
