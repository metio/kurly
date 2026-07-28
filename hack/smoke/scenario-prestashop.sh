#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Hand-written: PrestaShop runs on MySQL, which the generator only infers from a
# port or engine name appearing in the stage — this one names neither.
# e2e for the prestashop workload: provision its declared dependencies (a throwaway
# postgres/valkey at the service names it defaults to), mint the Secret it reads
# from the catalog secretKeys, then boot every stage and wait for health.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns=kurly-prestashop
kurly::namespace "$ns"

kurly::mysql "$ns" prestashop-db prestashop prestashop

kurly::secret "$ns" prestashop workloads/prestashop/server.libsonnet
kurly::boot workloads/prestashop/server.libsonnet "$ns" "+ k.env({ PS_INSTALL_AUTO: '1', PS_DOMAIN: 'prestashop', PS_HANDLE_DYNAMIC_DOMAIN: '0', PS_ERASE_DB: '0' })"
