// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// The stageset-controller migration ladder for tik: version-gated action
// ladders that run once when a version boundary is crossed, anchored before a
// named stage. tik's store is an append-only log whose stage is derived on
// read, so a migration re-derives or verifies rather than rewriting events.
// Actions are stageset-controller Action objects, passed through verbatim. The
// `to`/`from` boundaries are the workload's version — the calver the release
// stamps as app.kubernetes.io/version — so set them to your own release dates;
// the values here are illustrative.
local kurly = import 'github.com/metio/kurly/main.libsonnet';

[
  // Crossing up to 2026.9.1 re-derives the board: a new canonical format version
  // or new pinned process definitions change what the events derive to, so
  // `tik reprocess` runs as a job before the backend stage applies the new
  // image — derivations move to the new rules under a boundary dev has proven.
  kurly.migrations.migration('reprocess-on-format-bump', to='2026.9.1', stage='backend', actions=[
    {
      name: 'reprocess-tickets',
      job: {
        sourceRef: { kind: 'ExternalArtifact', name: 'tik-migration-jobs' },
      },
    },
  ]),

  // Installations on an earlier release verify store integrity before rolling
  // the supervisor onto 2026.6.1: `tik verify` re-derives every event byte-exact
  // to its hash and every signature to its key, so the new binary never adopts
  // a corrupt store. The job's non-zero exit fails the migration and blocks the
  // stage.
  kurly.migrations.migration('verify-store-before-upgrade', to='2026.6.1', from='>=2026.1.1, <2026.6.1', stage='backend', actions=[
    {
      name: 'verify-store-integrity',
      job: {
        sourceRef: { kind: 'ExternalArtifact', name: 'tik-verify-job' },
      },
    },
  ]),
]
