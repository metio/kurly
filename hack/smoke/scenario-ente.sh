#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the ente workload. Museum (the server) reads its whole configuration —
# database connection, S3 buckets, JWT secrets — from a credentials.yaml it takes
# from a Secret, which kurly deliberately authors none of. The smoke supplies the
# smallest one that lets it start against the throwaway PostgreSQL, so the boot
# proves the image, the mount path, and the health endpoint still line up.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns=kurly-ente
kurly::namespace "$ns"

kurly::postgres "$ns" ente-db-rw ente ente

kurly::prereq ente "$ns"

kurly::boot workloads/ente/server.libsonnet "$ns"
kurly::boot workloads/ente/web.libsonnet "$ns"
