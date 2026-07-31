#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the mailu workload. Its six stages share ONE volume — the mail store,
# the TLS material, and the filter state all live on it — which the workload
# deliberately does not create, because the claim is the operator's decision
# (ReadWriteMany on a real cluster, one node here). The scenario creates it, then
# provisions the cache and boots every stage.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns=kurly-mailu
kurly::namespace "$ns"

# Mailu addresses Redis without credentials, so the cache is left open.
kurly::cache "$ns" mailu-cache ""

# The shared claim every stage mounts.
kurly::prereq mailu "$ns"

kurly::secret "$ns" mailu workloads/mailu/admin.libsonnet
kurly::boot workloads/mailu/admin.libsonnet "$ns"
kurly::secret "$ns" mailu workloads/mailu/antispam.libsonnet
kurly::boot workloads/mailu/antispam.libsonnet "$ns"
kurly::secret "$ns" mailu workloads/mailu/front.libsonnet
kurly::boot workloads/mailu/front.libsonnet "$ns"
kurly::secret "$ns" mailu workloads/mailu/imap.libsonnet
kurly::boot workloads/mailu/imap.libsonnet "$ns"
kurly::secret "$ns" mailu workloads/mailu/smtp.libsonnet
kurly::boot workloads/mailu/smtp.libsonnet "$ns"
kurly::secret "$ns" mailu workloads/mailu/webmail.libsonnet
kurly::boot workloads/mailu/webmail.libsonnet "$ns"
