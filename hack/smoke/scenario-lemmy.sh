#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the lemmy workload. The backend reads a lemmy.hjson holding the instance's
# identity, its database connection, and the shared pict-rs key — kurly authors
# none, so the smoke supplies the smallest one that lets all three stages (backend,
# pict-rs, UI) come up against the throwaway PostgreSQL.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns=kurly-lemmy
kurly::namespace "$ns"

kurly::postgres "$ns" lemmy-db-rw lemmy lemmy


kurly::prereq lemmy "$ns"

kurly::boot workloads/lemmy/pictrs.libsonnet "$ns"
kurly::boot workloads/lemmy/backend.libsonnet "$ns"
kurly::boot workloads/lemmy/ui.libsonnet "$ns"
