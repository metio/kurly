// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// Software this catalogue will not carry, and why. catalog.jsonnet REFUSES TO
// BUILD if an id named here reappears in annotations.libsonnet, so a workload
// removed on purpose cannot drift back in unnoticed — which is the whole point of
// writing the decision down rather than deleting a directory and hoping.
//
// THE LINE: kurly packages software whose SOURCE is published. That is narrower
// than "open source" in one direction and wider in another, and both are
// deliberate:
//
//   - Source-available licences STAY. BUSL, SSPL, Elastic, PolyForm and the
//     various sustainable-use licences are not OSI-approved, and 13 workloads
//     carry one. Their source is published, they are self-hostable, and the
//     catalogue already says `licenseOsiApproved: false` so a consumer selling
//     open source can see exactly what it is looking at. Removing them would be
//     deciding somebody else's licensing policy for them.
//   - `licenseOsiApproved` is NOT the test. privatebin is zlib-acknowledgement,
//     which SPDX does not list as OSI-approved and which is plainly free
//     software. A flag derived from a list is evidence, not a verdict.
//
// What is excluded is software with no published source at all.
//
// REMOVING SOMETHING DOES NOT UNPUBLISH IT: images already released under
// ghcr.io/metio/kurly/workloads/<name> stay where they are, and a consumer pinning
// one by digest is unaffected. This list stops the catalogue carrying it, nothing
// more.
{
  // Proprietary media servers and a proprietary sync tool. Each publishes a
  // container image and no source, so the `upstream` field a consumer would use to
  // read, audit or fund the software has nothing to point at — the absence is not
  // a gap in kurly's annotations, it is the shape of the thing.
  emby: 'proprietary (LicenseRef-Proprietary); no published source repository',
  plex: 'proprietary (LicenseRef-Proprietary); no published source repository',
  'resilio-sync': 'proprietary (LicenseRef-Proprietary); no published source repository',

  // Licences that forbid, or are designed to forbid, exactly what a hosting portal
  // does: offer the software as a service to third parties. SSPL and the
  // sustainable-use and commons-clause-style licences say so outright; BUSL says it
  // for a term of years; Elastic-2.0 forbids providing the software "to others as a
  // managed service". Whatever a court would make of each, the intent is not in
  // doubt, and packaging them for a portal to sell would be working against their
  // authors' stated wishes.
  //
  // Note this is a decision about HOSTING them commercially, not a judgement on the
  // licences. Anyone may still run these themselves; kurly simply is not the thing
  // that helps them do it.
  browserless: 'SSPL-1.0 (or a commercial licence); forbids offering the software as a service',
  bugsink: 'PolyForm Shield 1.0.0; forbids use in a competing product or service',
  directus: 'BUSL-1.1; forbids offering the software as a service for the licence term',
  dragonfly: 'BUSL-1.1; forbids offering the software as a service for the licence term',
  emqx: 'BUSL-1.1; forbids offering the software as a service for the licence term',
  invoiceninja: 'Elastic-2.0; forbids providing the software to others as a managed service',
  mongo: 'SSPL-1.0; forbids offering the software as a service without releasing the service source',
  'mongodb-cluster': 'SSPL-1.0; same, via the operator that runs it',
  n8n: 'n8n Sustainable Use Licence; forbids offering the software as a service',
  nocodb: 'NocoDB Sustainable Use Licence; forbids offering the software as a service',
  outline: 'BUSL-1.1; forbids offering the software as a service for the licence term',
  planka: 'PLANKA Community licence; forbids offering the software as a service',
}
