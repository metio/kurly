// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// An in-cluster HTTP API: Deployment and Service, reached via the Service DNS
// name (users.<namespace>.svc). No exposure recipe — nothing outside the
// cluster talks to it.
local kurly = import '../main.libsonnet';

kurly.list(
  kurly.http.new('users', 'ghcr.io/example/users-api:2.4.1')
  .withPort(3000)
  .withHttpProbes('/healthz')
  .withEnv({
    DATABASE_HOST: 'postgres.databases.svc',
    LOG_LEVEL: 'info',
  })
  .withResources(limits={ memory: '256Mi' })
)
