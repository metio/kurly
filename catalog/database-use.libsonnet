// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// How many tables each workload created in the database the deep walk gave it,
// with the engine it was given and the date it was read. Written by
// hack/smoke/deep-run.sh as it walks, the same way the delivery ledger is.
//
// WHY THE COUNT IS KEPT RATHER THAN A VERDICT: zero tables does not mean broken.
// wordpress and prestashop create none until somebody completes their web
// installer, so zero is correct for them and damning almost everywhere else, and
// no absolute threshold can tell those apart.
//
// A workload's OWN PREVIOUS READING can. Compared against the last walk rather
// than against a constant:
//
//   wrote tables before, zero now  -> a regression, and unambiguous
//   zero before, zero now          -> no signal, and nobody had to know about the
//                                     installer
//   no previous reading            -> a warning, until it has one
//
// That is the same rule the rest of this repository runs on — a check has teeth
// only where two independent things can disagree — with the two things being the
// same workload at two moments instead of two sources.
//
// The failure mode is a baseline captured while the workload was already broken,
// which pins zero as normal for something that ought to write. It can only ever
// suppress an alarm, never raise a false one, and the zero set is small enough to
// read: projectsend is in it, and its delivery failed outright.
//
// This is deliberately SEPARATE from delivered-verified.libsonnet. A delivery
// claims the pipeline built, pulled, rendered, applied and rolled out; it never
// claimed the workload could use its database, which is why four workloads passed
// it against a database they could not use. Two facts, two files.

{
  photoview: { tables: 14, engine: 'postgres', on: '2026-07-31' },
  rallly: { tables: 31, engine: 'postgres', on: '2026-07-31' },
  redmine: { tables: 60, engine: 'mysql', on: '2026-07-31' },
}
