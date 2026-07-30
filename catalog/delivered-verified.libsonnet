// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// The workloads observed being DELIVERED end to end on a live cluster — built as a
// source image, pulled by Flux (OCIRepository), rendered by JaaS (JsonnetSnippet),
// and applied by stageset-controller (StageSet) until every controller rolled out
// — and the date it last happened. This is the evidence behind `maturity.delivered`.
//
// It is an AXIS, not a rung on the tier ladder, for the same reason production use
// is one: it answers a different question. The tier says how far the workload has
// been proven; this says the delivery path itself was walked — the image packaging,
// the vendor tree layout, the imports resolving inside JaaS, and the stage going
// Ready. A workload can boot fine under kubectl and still fail here, since a stage
// whose import path is wrong renders identically from the checkout and not at all
// from its image.
//
// Keeping it off the ladder is what lets a consumer that has never heard of it
// carry on reading `tier` correctly. Folding it in would make every such consumer
// treat the unfamiliar value as the weakest rung, and report the best-proven
// workloads in the catalogue as never having been booted.
//
// A workload is added when `hack/smoke/deep-run.sh` (or the e2e pipeline) observes
// its deep check green. Remove it if that starts failing; the tier must never claim
// more than the run proves. Workloads whose stages render only a custom resource
// have no controller to roll out and cannot reach this tier at all.
{
  '2fauth': '2026-07-30',
  activepieces: '2026-07-30',
  actualbudget: '2026-07-30',
  adguardhome: '2026-07-30',
  adminer: '2026-07-30',
  'airsonic-advanced': '2026-07-30',
  alist: '2026-07-30',
  answer: '2026-07-30',
  anythingllm: '2026-07-30',
  apprise: '2026-07-30',
  audiobookshelf: '2026-07-30',
  authelia: '2026-07-30',
  baikal: '2026-07-30',
  gatus: '2026-07-30',
  'it-tools': '2026-07-30',
  linkding: '2026-07-30',
  memos: '2026-07-30',
  'uptime-kuma': '2026-07-30',
  valkey: '2026-07-30',
  vaultwarden: '2026-07-30',
  whoogle: '2026-07-30',
}
