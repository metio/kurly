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
// the repository proves. production use is a separate, operator-attested axis
// (production.libsonnet): a workload can be e2e-tested without running in
// production, or in production without a smoke scenario.
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

  // The full maturity object for a workload: its tier, plus the production record
  // when the operator has attested one.
  of(name)::
    { tier: tierOf(name) }
    + (if std.objectHas(production, name) then { production: production[name] } else {}),

  // Every name the operator attested must be a real workload; catch a typo or a
  // renamed workload here rather than shipping a dangling claim.
  productionNames:: std.objectFields(production),
}
