// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// An in-cluster HTTP API: Deployment and Service, reached via the Service DNS
// name (users.<namespace>.svc). No exposure feature — nothing outside the
// cluster talks to it.
local kurly = import '../main.libsonnet';

kurly.list(
  kurly.http('users', 'ghcr.io/example/users-api:2.4.1')
  + kurly.port(3000)
  + kurly.probes('/healthz')
  + kurly.env({
    DATABASE_HOST: 'postgres.databases.svc',
    LOG_LEVEL: 'info',
  })
  + kurly.resources(limits={ memory: '256Mi' })
  // The API serves its metrics on the same port it serves traffic, so the
  // ServiceMonitor scrapes the workload's named `http` port — the pairing the
  // cross-manifest policy checks stays green here.
  + kurly.serviceMonitor(path='/metrics')
)
