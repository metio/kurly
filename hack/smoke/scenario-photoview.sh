#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Hand-written: the generator reads the MySQL alternative this workload documents and
# provisions MariaDB, but the Secret drives it with a PostgreSQL URL — so the
# dependency is pinned here to the engine the smoke actually configures.
# e2e for the photoview workload: provision its declared dependencies (a throwaway
# postgres/valkey at the service names it defaults to), mint the Secret it reads
# from the catalog secretKeys, then boot every stage and wait for health.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns=kurly-photoview
kurly::namespace "$ns"

kurly::postgres "$ns" photoview-db-rw photoview photoview

kurly::secret "$ns" photoview workloads/photoview/server.libsonnet
kurly::boot workloads/photoview/server.libsonnet "$ns"
