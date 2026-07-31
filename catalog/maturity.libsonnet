// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// A workload's maturity: how far it has been proven. The tier is a ladder, each
// rung a stronger claim than the last:
//
//   rendered — renders and validates (kubeconform) with defaults. Every
//              catalogued workload clears this by construction.
//   tested   — plus workload-specific assertions in the test suite.
//   e2e      — plus a smoke scenario that deploys it to a live cluster and waits
//              for it to become ready.
//
// The tier is derived from the repository's own signals (maturity.gen.libsonnet,
// regenerated and drift-checked by check-catalog), so it cannot claim more than
// the repository proves.
//
// TWO further axes travel alongside it, and neither is a rung. A rung is a
// stronger version of the same claim, so a consumer may read the ladder as an
// ordering and take the highest one it knows. These answer DIFFERENT questions,
// and a consumer that has not heard of one must be able to ignore it without
// misreading the workload:
//
//   production — an operator attests it runs in production (production.libsonnet).
//   delivered  — it was driven end to end through the real delivery path, Flux ->
//                JaaS -> stageset-controller, and its controllers rolled out
//                (delivered-verified.libsonnet).
//
// A workload can be e2e-tested without either, delivered without running in
// production, or in production with no scenario at all. Folding any of them into
// the ladder would also make every consumer that switches on `tier` treat the
// unfamiliar value as the WEAKEST rung — turning the strongest evidence there is
// into "never booted", which is the opposite of what it says.
// A delivery that created tables in its database and one that never touched it
// are not equally strong evidence, and the difference lands on the failure class
// that matters most for an upgrade: a version that booted AND RAN ITS MIGRATIONS
// under the walk is a materially stronger claim than one that merely booted. So
// where the walk read a schema, the count travels with the delivery that produced
// it. Absent means nobody read one — never that the workload wrote nothing, which
// is `databaseTables: 0`.
local databaseUse = import './database-use.libsonnet';
local delivered = import './delivered-verified.libsonnet';
local derived = import './maturity.gen.libsonnet';
local production = import './production.libsonnet';

// The highest derived tier a workload has reached. A top-level local, so the
// `of` method below can call it without `self` rebinding to its object literal.
local tierOf(name) =
  if std.member(derived.e2e, name) then 'e2e'
  else if std.member(derived.tested, name) then 'tested'
  else 'rendered';

{
  tierOf(name):: tierOf(name),

  // The full maturity object for a workload: its tier, plus each axis that has
  // something to say about it. Both carry the date their evidence was observed,
  // because an attestation nobody has repeated in two years is a different fact
  // from one made last week.
  of(name)::
    { tier: tierOf(name) }
    + (if std.objectHas(production, name) then { production: production[name] } else {})
    + (
      if std.objectHas(delivered, name)
      then {
        delivered: { since: delivered[name] }
                   + (
                     if std.objectHas(databaseUse, name)
                     then {
                       databaseTables: databaseUse[name].tables,
                       databaseEngine: databaseUse[name].engine,
                       databaseReadOn: databaseUse[name].on,
                     }
                     else {}
                   ),
      }
      else {}
    ),

  // Every name either axis claims must be a real workload; catch a typo or a
  // renamed workload here rather than shipping a dangling claim.
  productionNames:: std.objectFields(production),
  deliveredNames:: std.objectFields(delivered),
  databaseUseNames:: std.objectFields(databaseUse),
}
