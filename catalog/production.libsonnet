// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// Operator-attested production use, keyed by workload id. Unlike the e2e and
// tested tiers (derived from CI signals in maturity.gen.libsonnet), this is a
// claim only the cluster's operator can make, so it is hand-maintained here.
//
// Each entry records the date the workload went into production and the cluster
// it runs on. The date is an ISO 'YYYY-MM-DD' string; the reference site turns it
// into a running day count, and a workload's README shows the date. Add an entry
// when a workload has genuinely been running a real workload — not before.
//
//   'tik': { since: '2026-05-01', cluster: 'staging' },
{
}
