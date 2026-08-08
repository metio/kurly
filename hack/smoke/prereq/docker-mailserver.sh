# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# docker-mailserver refuses to start without a mailbox: it waits two minutes for
# one and then shuts the container down, so an account is a prerequisite of
# booting rather than a first task afterwards. The account list is a document a
# deployment writes — one `address|{SCHEME}hash` line per mailbox — and kurly
# authors none, so the smoke supplies the smallest one that starts: a single
# throwaway mailbox, its password in the plaintext scheme Dovecot reads from the
# entry's own prefix.
#
# Sourced with $ns set, by the fast scenario and by the deep check alike.

: "${ns:?prerequisites are sourced by kurly::prereq, which sets ns}"

accounts="$(mktemp)"
trap 'rm -f "$accounts"' EXIT
printf 'smoke@example.com|{PLAIN}%s\n' "$KURLY_E2E_PASSWORD" >"$accounts"

kubectl --namespace="$ns" create secret generic docker-mailserver \
  --from-file=postfix-accounts.cf="$accounts" --dry-run=client --output=yaml | kubectl apply --filename=-
