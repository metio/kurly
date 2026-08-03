// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// What a project's own TRADEMARK POLICY says about using its name and logo.
//
// A trademark policy is in force whether or not the people holding it have ever
// heard of anybody running this catalogue. That makes it a different kind of
// fact from consent.libsonnet, which records something a maintainer SENT us:
//
//   consent    absent means NOBODY ASKED, so nobody objected.
//   trademark  absent means WE DO NOT KNOW, and unknown is NOT permission.
//
// Most of the catalogue sits at unknown, and that is the honest state rather
// than a gap to be filled with a guess. A consumer that reads an absent entry as
// "go ahead" is asserting a licence nobody granted; what it does with unknown is
// its own decision, but it must be able to tell unknown from permitted.
//
// NEVER DERIVED FROM THE LICENCE. The code licence and the trademark are
// separate grants and they routinely disagree — a permissively licensed project
// with a strict mark is the ordinary case, not the exception. A posture inferred
// from `license` would be a guess wearing the clothes of a fact, which is the one
// thing this catalogue does not publish.
//
// NOT WHETHER WE HOLD PERMISSION. Partner programmes exist, and being a partner
// is a fact about one deployment rather than about the software. That belongs in
// an operator's own configuration, so that a fork holding different permissions
// says so without editing this file. A record here describes what the PROJECT
// published, full stop.
//
// NOT A LEGAL DETERMINATION either. Whether a particular listing is nominative
// use is a question for a lawyer and for the operator asking it. This file
// records what the policy says and links it, so the answer to "why is it listed
// under that name" points at the project's own page instead of at somebody's
// reading of it.
//
// ── the shape ───────────────────────────────────────────────────────────────
//
//   '<workload-id>': {
//     posture: 'restricted' | 'unrestricted',
//     policy: '<url>',                  // required: the page this was read from
//     neutralName: '<name>',            // optional, and only where the project
//                                       // or common practice offers one — not
//                                       // a name invented here
//     note: '<what the policy actually restricts>',   // optional
//   }
//
// `policy` is required because a posture with nothing behind it is an assertion
// about somebody else's rights with no way to check it. Absent from this file
// entirely is the right way to say "we have not looked".
{
  // Read from the policy itself rather than from reputation. It permits using
  // the name to promote a project built on WordPress, and then restricts the two
  // places a hosting listing would most naturally put it:
  //
  //   "Under no circumstances is it permitted to use WordPress or WordCamp as
  //    part of a domain name or top-level domain name."
  //   "Please do not use 'WP' in any way that confuses people."
  //
  // The domain-name line is the one worth noticing early: a URL is the hardest
  // thing to change later, because every link anybody saved breaks with it.
  wordpress: {
    posture: 'restricted',
    policy: 'https://wordpressfoundation.org/trademark-policy/',
    note: 'The name may be used to describe a project built on WordPress, but never as part of a domain name; "WP" must not be used confusingly.',
  },
}
