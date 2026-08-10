#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the netbox workload. NetBox reads its secrets as FILES under /run/secrets
# rather than from the environment, and it addresses Redis without credentials —
# so the cache is left open, which the generated scenario cannot express.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

# NetBox migrates a large schema and builds its static assets before it answers,
# which takes around seven minutes here — well past the default rollout ceiling.
export KURLY_ROLLOUT_TIMEOUT=900

ns="$(kurly::namespace_unique kurly-netbox)"
kurly::namespace "$ns"

kurly::postgres "$ns" netbox-db-rw netbox netbox
kurly::cache "$ns" netbox-cache ""

kurly::secret "$ns" netbox workloads/netbox/server.libsonnet
kurly::boot workloads/netbox/server.libsonnet "$ns"
kurly::secret "$ns" netbox workloads/netbox/worker.libsonnet
kurly::boot workloads/netbox/worker.libsonnet "$ns"
