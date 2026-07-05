// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// worker: a queue consumer or background processor — a Deployment with no
// Service and no ports. Scale it with withReplicas.
local base = import './base.libsonnet';

{
  new(name, image)::
    base.core(name, image)
    + base.deployment,
}
