#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the chibisafe workload. The three stages are one installation, not three
# independent ones: the proxy serves the uploads straight off the server's claim,
# so it only schedules where that claim already exists. They therefore share one
# namespace and boot in dependency order — server (which creates the claim),
# frontend, then the proxy in front of both.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns=kurly-chibisafe
kurly::namespace "$ns"

kurly::secret "$ns" chibisafe workloads/chibisafe/server.libsonnet
kurly::boot workloads/chibisafe/server.libsonnet "$ns"
kurly::boot workloads/chibisafe/frontend.libsonnet "$ns"
kurly::boot workloads/chibisafe/proxy.libsonnet "$ns"
