#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Hand-written: Twenty builds its Redis URL from a host name alone, with no place
# for credentials, so the cache is left open.
# e2e for the twenty workload: provision its declared dependencies (a throwaway
# postgres/valkey at the service names it defaults to), mint the Secret it reads
# from the catalog secretKeys, then boot every stage and wait for health.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns=kurly-twenty
kurly::namespace "$ns"

kurly::postgres "$ns" twenty-db-rw twenty twenty
kurly::cache "$ns" twenty-cache ""

kurly::secret "$ns" twenty workloads/twenty/server.libsonnet
kurly::boot workloads/twenty/server.libsonnet "$ns" "+ k.env({ SERVER_URL: 'http://twenty:3000' })"
kurly::secret "$ns" twenty workloads/twenty/worker.libsonnet
kurly::boot workloads/twenty/worker.libsonnet "$ns" "+ k.env({ SERVER_URL: 'http://twenty:3000' })"
