// SPDX-FileCopyrightText: The kurly Authors
// SPDX-License-Identifier: 0BSD

// Memory limits a workload has been PROVEN to need more than, because the kernel
// killed it at that limit. Written by hack/smoke/deep-run.sh as it walks.
//
// This is the only kind of resource floor anybody here has established. A stage's
// declared `requests` is a hand-set guess (published as `declaredRequests`, and
// explicitly not a minimum); a sampled peak says what a fresh install USED, which
// is not what it NEEDS. An OOMKill says something different and much stronger: at
// this limit, this workload died. That is not an observation about typical use, it
// is a bound.
//
// So an entry reads: `oomKilledAt: '512Mi'` means the workload needs MORE than
// 512Mi. It does not say how much more — establishing that would mean re-running at
// increasing sizes until it survives, which is a search rather than a test, and the
// walk runs each workload once.
//
// WHY ONLY OOMKilled, and not "the workload failed at this size": most failures say
// nothing whatever about resources. In one afternoon the walk failed rocketchat for
// being handed a PostgreSQL when it wants MongoDB, prestashop on an installer lock,
// projectsend inside its s6 init, and thirteen more because a git rebase moved the
// tree while they were rendering. Filing any of those as evidence of a memory floor
// would manufacture precisely the confident-wrong number this repository has spent
// two days removing. The kernel killing a container for exceeding its limit is a
// resource fact; a workload failing is not.
//
// Coverage is therefore low and uneven by construction — each workload runs at one
// size, so nothing is learned unless that size happens to be too small. Empty is
// the expected state. Every entry in it is true, which is the trade.

{
  shlink: { oomKilledAt: '512Mi', on: '2026-08-01' },
}
