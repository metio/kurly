// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// A stageset-controller migration ladder for the staged shop workload: a
// plain []Migration array, packed into the workload image's migrations layer
// and consumed via a StageSet's spec.migrationsSourceRef. Each entry gates on
// a version boundary; actions are stageset-controller Action objects passed
// through verbatim.
local kurly = import '../../main.libsonnet';

[
  // Crossing up to 2.0.0 recreates the worker Deployment: its selector
  // changed, and selectors are immutable, so the old object must go before
  // the new spec applies. Orphan cascade keeps the pods running while the
  // re-applied Deployment adopts them.
  kurly.migrations.migration('recreate-worker-deployment', to='2.0.0', actions=[
    {
      name: 'drop-old-deployment',
      delete: {
        target: { kind: 'Deployment', name: 'shop-worker' },
        cascade: 'Orphan',
      },
    },
  ]),

  // Only installations already on 2.x run the index backfill, anchored just
  // before the production stage so dev has proven the boundary first.
  kurly.migrations.migration('backfill-search-index', to='2.1.0', from='>=2.0.0, <2.1.0', stage='production', actions=[
    {
      name: 'run-backfill-jobs',
      job: {
        sourceRef: { kind: 'ExternalArtifact', name: 'shop-migration-jobs' },
      },
    },
  ]),
]
