#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Hand-written: paperless builds its Redis URL from a host name alone, with no place
# for credentials, so the cache is left open.
# e2e for the paperless-ngx workload: provision its declared dependencies (a throwaway
# postgres/valkey at the service names it defaults to), mint the Secret it reads
# from the catalog secretKeys, then boot every stage and wait for health.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns=kurly-paperless-ngx
kurly::namespace "$ns"

kurly::postgres "$ns" paperless-db-rw paperless paperless
kurly::cache "$ns" paperless-cache ""

kurly::secret "$ns" paperless-ngx workloads/paperless-ngx/server.libsonnet
kurly::boot workloads/paperless-ngx/server.libsonnet "$ns"
