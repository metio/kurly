// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// A nightly job: a CronJob that never overlaps its own runs (concurrencyPolicy
// Forbid) and retries failed containers (OnFailure). The schedule is a
// required argument of the kind.
local kurly = import '../main.libsonnet';

kurly.list(
  kurly.cron('db-backup', 'ghcr.io/example/backup:3.1.0', '13 3 * * *')
  + kurly.serviceAccount('backup')
  + kurly.env({ TARGET_BUCKET: 's3://backups/db' })
  // Backup tooling writes scratch files, so this job opts out of the
  // read-only root filesystem — the rest of the restricted profile stays.
  + kurly.writableRootFilesystem()
)
