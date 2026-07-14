// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// The stageset-controller migration ladder for tik: version-gated action
// ladders that run once when a version boundary is crossed, anchored before a
// named stage. tik's store is an append-only log whose stage is derived on
// read, so a migration never rewrites events — it re-derives or verifies.
// Actions are stageset-controller Action objects, passed through verbatim.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

[
  // Crossing up to 2.0.0 re-derives the board: a new canonical format version
  // or new pinned process definitions change what the events derive to, so
  // `tik reprocess` runs as a job before the backend stage applies the new
  // image — derivations move to the new rules under a boundary dev has proven.
  kurly.migrations.migration('reprocess-on-format-bump', to='2.0.0', stage='backend', actions=[
    {
      name: 'reprocess-tickets',
      job: {
        sourceRef: { kind: 'ExternalArtifact', name: 'tik-migration-jobs' },
      },
    },
  ]),

  // Only installations already on 1.x verify store integrity before rolling
  // the supervisor onto 1.5.0: `tik verify` re-derives every event byte-exact
  // to its hash and every signature to its key, so the new binary never adopts
  // a corrupt store. The job's non-zero exit fails the migration and blocks the
  // stage.
  kurly.migrations.migration('verify-store-before-upgrade', to='1.5.0', from='>=1.0.0, <1.5.0', stage='backend', actions=[
    {
      name: 'verify-store-integrity',
      job: {
        sourceRef: { kind: 'ExternalArtifact', name: 'tik-verify-job' },
      },
    },
  ]),
]
