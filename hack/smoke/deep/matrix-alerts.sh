#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the seam between TWO workloads: continuwuity (a Matrix homeserver) and
# matrix-alertmanager-receiver (the webhook an Alertmanager posts alerts to).
#
# WHY THIS IS A DEEP SCENARIO. The receiver cannot be proven by the fast tier at
# all: it contacts a homeserver and fetches the rooms its account has joined
# BEFORE it serves, so a scenario with no homeserver watches it exit and learns
# nothing about the workload. Everything interesting about it is the pairing —
# whether the credential works, whether the room mapping resolves, and whether an
# Alertmanager payload actually arrives as a message somebody would read.
#
# Four assertions, each proving a link no render gate can:
#   1. The homeserver comes up and registers an account, yielding a real access
#      token — the credential the receiver's Secret is built from.
#   2. That account creates a room, and the receiver STARTS against it. Starting
#      is itself the assertion: the process fetches its joined rooms first, so a
#      Ready pod means the token authenticated and the mapped room resolved.
#   3. An Alertmanager-shaped payload posted to the webhook is accepted.
#   4. The alert ARRIVES IN THE ROOM, read back through the homeserver's own
#      client API — the only check that proves the message was delivered rather
#      than merely accepted, and the reason the other three are not enough.
cd "$(dirname "$0")/../../.." || exit 1
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh

ns=kurly-matrix-alerts
server_name=kurly.test
homeserver="http://continuwuity.${ns}.svc:8008"
receiver="http://matrix-alertmanager-receiver.${ns}.svc:12345"
user=alerts
password='Kurly-e2e-Passw0rd'

fail() {
  echo "::error::$*"
  kurly::diagnose "$ns"
  echo "::group::matrix alert path state"
  kubectl --namespace="$ns" get deployment,pods -o wide 2>/dev/null || true
  for app in continuwuity matrix-alertmanager-receiver; do
    echo "--- ${app} log ---"
    kubectl --namespace="$ns" logs --selector="app.kubernetes.io/name=${app}" --tail=40 2>/dev/null || true
  done
  echo "::endgroup::"
  exit 1
}

# Every request to either service runs from a pod in the namespace: the point is
# to prove the path a real Alertmanager takes, which is Service to Service inside
# the cluster, not something reachable from a laptop through a port-forward.
curl_in() { kubectl --namespace="$ns" exec matrix-client -- curl "$@"; }

kurly::vendor
kurly::namespace "$ns"

# ---------------------------------------------------------------------------
# Assertion 1 — a homeserver, and an account on it with a real access token
# ---------------------------------------------------------------------------

echo "== deploy continuwuity =="
# Registration is opened deliberately and only here: this scenario has to create
# the account the receiver posts as, and there is no other way to obtain a token
# from a homeserver nobody has logged into.
kurly::render workloads/continuwuity/server.libsonnet \
  "+ k.hostUsers()" "serverName='${server_name}', allowRegistration=true" \
  | kubectl apply --namespace="$ns" --filename=-
kubectl --namespace="$ns" rollout status deployment/continuwuity --timeout=300s \
  || fail "the homeserver never became Ready"

echo "== a curl client =="
kubectl --namespace="$ns" run matrix-client --image=docker.io/curlimages/curl:8.21.0 \
  --restart=Never --command -- sleep 3600
kubectl --namespace="$ns" wait --for=condition=Ready pod/matrix-client --timeout=120s \
  || fail "the client pod never became Ready"

echo "== register @${user}:${server_name} =="
# THE REGISTRATION TOKEN IS READ FROM THE SERVER'S OWN LOG. Continuwuity mints
# one for the first account and announces it there; setting CONDUWUIT_REGISTRATION_TOKEN
# does not replace it, which is only visible by trying — the server keeps offering
# the registration-token flow either way and answers a wrong token with
# "Invalid registration token" rather than saying the setting was ignored.
regtoken=""
for _ in $(seq 1 20); do
  regtoken="$(kubectl --namespace="$ns" logs --selector=app.kubernetes.io/name=continuwuity --tail=200 2>/dev/null \
    | sed -e 's/\x1b\[[0-9;]*m//g' \
    | grep -oE 'registration token [A-Za-z0-9]+' | head -1 | awk '{print $3}')"
  [ -z "$regtoken" ] || break
  sleep 3
done
[ -n "$regtoken" ] || fail "the homeserver never announced a registration token"

# The Matrix user-interactive-auth dance: an opening request returns a session
# and the flows the server accepts, then the registration-token stage is answered
# against that session.
register() {
  curl_in -s -X POST -H 'Content-Type: application/json' \
    --data "$1" "${homeserver}/_matrix/client/v3/register?kind=user" 2>/dev/null || true
}
token=""
for _ in $(seq 1 20); do
  session="$(register "$(printf '{"username":"%s","password":"%s"}' "$user" "$password")" \
    | jq -r '.session // empty' 2>/dev/null || true)"
  if [ -n "$session" ]; then
    token="$(register "$(printf '{"username":"%s","password":"%s","auth":{"type":"m.login.registration_token","token":"%s","session":"%s"}}' \
      "$user" "$password" "$regtoken" "$session")" | jq -r '.access_token // empty' 2>/dev/null || true)"
  fi
  [ -z "$token" ] || break
  sleep 3
done
[ -n "$token" ] || fail "could not register an account on the homeserver — no access token"
echo "  registered, token obtained"

# ---------------------------------------------------------------------------
# Assertion 2 — a room, and a receiver that starts against it
# ---------------------------------------------------------------------------

echo "== create a room for the alerts =="
room="$(curl_in -sf -X POST -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${token}" \
  --data '{"name":"kurly alerts","preset":"private_chat"}' \
  "${homeserver}/_matrix/client/v3/createRoom" 2>/dev/null | jq -r '.room_id // empty' 2>/dev/null || true)"
[ -n "$room" ] || fail "could not create a room"
echo "  room: ${room}"

echo "== the Secret the receiver reads its token from =="
kubectl --namespace="$ns" create secret generic matrix-alertmanager-receiver \
  --from-literal=MATRIX_ACCESS_TOKEN="$token" \
  --dry-run=client -o yaml | kubectl apply --namespace="$ns" --filename=-

echo "== deploy matrix-alertmanager-receiver =="
kurly::render workloads/matrix-alertmanager-receiver/server.libsonnet \
  "+ k.hostUsers()" \
  "homeserverUrl='${homeserver}', userId='@${user}:${server_name}', roomMapping={ pager: '${room}' }" \
  | kubectl apply --namespace="$ns" --filename=-
# READY IS THE ASSERTION. The process fetches the rooms its account has joined
# before it listens, so it cannot become Ready with a token the homeserver
# rejects or a room id that does not resolve.
kubectl --namespace="$ns" rollout status deployment/matrix-alertmanager-receiver --timeout=300s \
  || fail "the receiver never became Ready — its token or its room mapping did not work"

# ---------------------------------------------------------------------------
# Assertion 3 — the webhook accepts an Alertmanager payload
# ---------------------------------------------------------------------------

echo "== post an alert, as an Alertmanager would =="
# The shape Alertmanager actually sends: a version, a status, and the alert list
# whose labels and annotations the templates read.
alert_body='{
  "version": "4",
  "status": "firing",
  "receiver": "matrix",
  "externalURL": "http://alertmanager:9093",
  "commonLabels": { "alertname": "KurlyProbe", "severity": "critical" },
  "alerts": [{
    "status": "firing",
    "labels": { "alertname": "KurlyProbe", "severity": "critical" },
    "annotations": { "description": "kurly deep scenario probe" },
    "generatorURL": "http://prometheus:9090",
    "startsAt": "2026-01-01T00:00:00Z"
  }]
}'
curl_in -sf -X POST -H 'Content-Type: application/json' \
  --data "$alert_body" "${receiver}/alerts/pager" >/dev/null 2>&1 \
  || fail "the receiver rejected the Alertmanager payload"

# ---------------------------------------------------------------------------
# Assertion 4 — the alert arrived in the room
# ---------------------------------------------------------------------------
#
# Accepting a webhook and delivering a message are different things, and only
# this check tells them apart: the receiver answers the POST before the message
# reaches Matrix, so a green assertion 3 with a silent room is exactly the
# failure a deployment would not notice until nobody was paged.
echo "== read the room back and look for the alert =="
delivered=false
for _ in $(seq 1 30); do
  body="$(curl_in -sf -H "Authorization: Bearer ${token}" \
    "${homeserver}/_matrix/client/v3/rooms/$(printf '%s' "$room" | jq -sRr @uri)/messages?dir=b&limit=20" \
    2>/dev/null || true)"
  if printf '%s' "$body" | jq -e '[.chunk[]? | select(.type == "m.room.message")
        | .content.body // .content.formatted_body // ""]
      | any(test("KurlyProbe"))' >/dev/null 2>&1; then
    delivered=true
    break
  fi
  sleep 3
done
[ "$delivered" = true ] || fail "the alert never arrived in the room — accepted by the webhook, never delivered to Matrix"

echo "ok: an Alertmanager alert travelled webhook -> receiver -> Matrix room"
