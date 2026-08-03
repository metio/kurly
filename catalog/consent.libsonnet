// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// What a project's MAINTAINERS have asked of anyone hosting their software
// commercially. One record per workload, and none today.
//
// ────────────────────────────────────────────────────────────────────────────
// HONOURING THESE IS A CHOICE. IT IS NOT A LEGAL OBLIGATION.
//
// Every licence in this catalogue permits commercial hosting. A maintainer who
// asks us to stop is asking for something no licence here requires, and we
// honour it because we would rather not run software over the objection of the
// people who wrote it. That is a policy, and the policy is the point.
//
// A later maintainer of this file may decide differently, and would be entitled
// to. What they must not do is treat this file as a compliance obligation,
// because the failure worth guarding against is not somebody removing the
// feature — it is somebody in two years honouring a bad-faith request on the
// grounds that "the schema says we honour these". The schema says nothing of
// the kind. It records what was asked and what evidence came with it; whether
// to act on a particular request is a judgement, every time.
//
// This also cuts the other way, which is why the evidence rules below are not
// ceremony. Because a record here propagates to every deployment reading the
// catalogue, it is a stronger lever than any one operator's exclusion list — and
// a project that is acquired, relicensed, or simply decides it wants the hosting
// market can reach for it. Evidence and reversibility are what make that
// acceptable rather than incidental to it.
// ────────────────────────────────────────────────────────────────────────────
//
// ABSENCE IS THE NORMAL STATE and means NOBODY ASKED. It does not mean the
// maintainers consent — nobody has been asked, so there is no consent to record.
// There is deliberately no `offered` status: carrying one on every workload
// would assert a conversation with each of them that never happened.
//
// SEPARATE FROM excluded.libsonnet, and the distinction is load-bearing. That
// file holds workloads WE decided not to carry — a licence that forbids offering
// the software as a service, an upstream that sells its own hosting, an archived
// repository. No maintainer asked for any of those. Folding the two together
// would publish our decision as though it were their wish, which is a
// misrepresentation of somebody else's position and the reason these are two
// files rather than one field.
//
// ── the shape ───────────────────────────────────────────────────────────────
//
//   '<workload-id>': {
//     status: 'no-new-orders' | 'winding-down',
//     asked: 'YYYY-MM-DD',       // when the maintainers asked. NOT a deadline:
//                                // an operator's notice period runs from the
//                                // day its customers are told, not from the day
//                                // somebody wrote to us — a request sitting
//                                // here for a month must not eat a month of
//                                // somebody's warning.
//     verifiedBy: 'repository-commit' | 'signed-email' | 'dns-txt',
//     evidence: '<url>',         // the thing a reader can go and check
//     statement: '<their words>',        // optional
//     statementPublishable: false,       // optional, DEFAULT FALSE
//     nameAndMark: 'yes' | 'no' | 'ask', // optional, a SEPARATE question
//   }
//
// NO RECORD WITHOUT EVIDENCE. `verifiedBy` and `evidence` are required, and the
// build rejects a record missing either. A claim about somebody else's wishes,
// published to every consumer of this catalogue, is not something to carry on
// the strength of a half-remembered mailing-list post. `verifiedBy` names the
// METHOD so the strength of a claim is inspectable rather than assumed: a file
// in the project's own repository demonstrates commit rights, where a DNS record
// demonstrates whoever holds the domain — which is the wrong question for a
// project living on github.io or a foundation's domain.
//
// `statement` is the maintainers' own words and `statementPublishable` defaults
// to FALSE. "The maintainers do not want this hosted" is a sentence that would
// be put in somebody's mouth; if they gave us one and said we may print it, it
// is printed verbatim and attributed, and otherwise a consumer shows the neutral
// fact and stops.
//
// `nameAndMark` is a DIFFERENT question from hosting and deliberately not a
// status. A maintainer can consistently say "run it, but not under our name and
// logo" — which the licences never covered either way, and which is likely the
// commoner objection. `ask` reads as no until somebody has actually asked.
//
// ── a worked example ────────────────────────────────────────────────────────
//
// Deliberately a made-up id. Naming a real project in an example would put a
// consent record beside a familiar name and invite a reader to conclude
// something nobody is entitled to conclude — which is the same mistake, at the
// scale of one project, that keeping this file separate from excluded.libsonnet
// avoids at the scale of fifty-five.
//
//   'example-workload': {
//     status: 'winding-down',
//     asked: '2026-08-03',
//     verifiedBy: 'repository-commit',
//     evidence: 'https://example.invalid/example/example/pull/1',
//     statement: 'We would rather run the hosted version ourselves.',
//     statementPublishable: true,
//     nameAndMark: 'no',
//   }
//
// ── records ─────────────────────────────────────────────────────────────────
//
// None. No maintainer has been asked and none has written to us. The file exists
// so a consumer can build against the shape, and so the first request has
// somewhere to go that is not a pull request against somebody's lockfile.
{
}
