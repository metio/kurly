#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the docker-mailserver workload. It refuses to start until a mailbox
# exists — two minutes of waiting and then the container shuts down — and the
# account list is a document kurly authors none of, so the smoke mints one
# throwaway mailbox into the Secret the stage mounts over its configuration
# volume. Booting it proves the image, the mail ports, the three volumes and the
# privileges Postfix and Dovecot need still line up.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh
kurly::vendor

ns=kurly-docker-mailserver
kurly::namespace "$ns"

kurly::prereq docker-mailserver "$ns"

kurly::boot workloads/docker-mailserver/server.libsonnet "$ns" "" "accountsSecret='docker-mailserver'"
