#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the dgraph workload. Hand-written rather than generated, because the
# generated shape cannot boot it: it gives every stage its own namespace and boots
# them in catalog order.
#
# Both facts break dgraph. The alphas resolve `dgraph-zero-headless` to find the
# coordinator that tells them which part of the graph they own, and a Service in
# another namespace does not answer that name at all — the generated run reported
# "produced zero addresses" for a zero that was running perfectly well next door.
# And zero must exist FIRST: an alpha started before it waits, and waits past the
# rollout timeout, so alphabetical order fails even in one namespace.
#
# So: one namespace, zero, then the alphas.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns="$(kurly::namespace_unique kurly-dgraph)"
kurly::namespace "$ns"

kurly::boot workloads/dgraph/zero.libsonnet "$ns" "" ""
kurly::boot workloads/dgraph/alpha.libsonnet "$ns" "" ""
