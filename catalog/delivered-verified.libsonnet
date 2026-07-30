// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// The workloads observed being DELIVERED end to end on a live cluster — built as a
// source image, pulled by Flux (OCIRepository), rendered by JaaS (JsonnetSnippet),
// and applied by stageset-controller (StageSet) until every controller rolled out
// — and the date it last happened. This is the evidence behind the `delivered`
// maturity tier, the rung above `e2e`.
//
// `e2e` proves the manifest runs when kubectl applies it. `delivered` proves the
// whole production path a consumer actually uses: the image packaging, the vendor
// tree layout, the imports resolving inside JaaS, and the stage going Ready. A
// workload can boot fine and still fail here — a stage whose import path is wrong
// renders identically from the checkout and not at all from its image.
//
// A workload is added when `hack/smoke/deep-run.sh` (or the e2e pipeline) observes
// its deep check green. Remove it if that starts failing; the tier must never claim
// more than the run proves. Workloads whose stages render only a custom resource
// have no controller to roll out and cannot reach this tier at all.
{
  gatus: '2026-07-30',
  'it-tools': '2026-07-30',
  linkding: '2026-07-30',
  memos: '2026-07-30',
  'uptime-kuma': '2026-07-30',
  valkey: '2026-07-30',
  vaultwarden: '2026-07-30',
  whoogle: '2026-07-30',
}
