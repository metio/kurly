// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// A queue consumer: a Deployment with no Service and no ports. The explicit
// ServiceAccount also mounts its API token — workloads without one run
// token-less.
local kurly = import '../main.libsonnet';

kurly.list(
  kurly.worker.new('mailer', 'ghcr.io/example/mailer:1.8.0')
  .withReplicas(2)
  .withServiceAccount('mailer')
  .withEnv({ QUEUE_URL: 'nats://nats.messaging.svc:4222' })
)
