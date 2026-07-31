#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the misskey workload. Misskey is configured by a default.yml holding the
# instance URL and its database and Redis connections — kurly authors none, because
# it carries credentials — so the smoke supplies the smallest one that boots the
# server against the throwaway PostgreSQL and Valkey.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns=kurly-misskey
kurly::namespace "$ns"

kurly::postgres "$ns" misskey-db-rw misskey misskey
kurly::cache "$ns" misskey-cache-headless ""

kurly::prereq misskey "$ns"

kurly::boot workloads/misskey/server.libsonnet "$ns"
