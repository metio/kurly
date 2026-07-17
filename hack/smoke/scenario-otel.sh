#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# e2e for the otel-collector agent, proving the two things about a per-node
# OpenTelemetry Collector that only a cluster can show.
#
# The collector's config is the whole workload, and kurly renders it verbatim
# from a Jsonnet document into the mounted file. A collector VALIDATES that config
# on boot — an exporter a pipeline names but never defines, a receiver with a bad
# endpoint, a processor that isn't wired — and exits rather than run half-built.
# So a DaemonSet that reaches Ready is itself the proof that the rendered YAML is
# a real, valid collector config, not just well-formed text the render gates
# accept. The second thing is that it SERVES: the OTLP receiver actually listens
# and accepts telemetry, which no manifest check can establish.
#
# Two assertions:
#   1. The DaemonSet becomes Ready on the node — the config booted.
#   2. An OTLP/HTTP trace POSTed to the collector is accepted (HTTP 2xx) and
#      lands in the debug exporter's log — the pipeline received → processed →
#      exported it end to end.
cd "$(dirname "$0")/../.."
# shellcheck source=hack/smoke/lib.sh
source hack/smoke/lib.sh

ns=kurly-otel
app=otel-collector

fail() {
  echo "::error::$*"
  kurly::diagnose "$ns"
  echo "::group::otel-collector state"
  kubectl --namespace="$ns" get daemonset,pods -o wide 2>/dev/null || true
  # A collector that rejected its config prints the reason (the offending
  # component) to its log and exits — it appears nowhere else.
  kubectl --namespace="$ns" logs --selector="app.kubernetes.io/name=${app}" --tail=60 2>/dev/null || true
  echo "::endgroup::"
  exit 1
}

kurly::vendor
kurly::namespace "$ns"

echo "== apply the otel-collector agent =="
# kind-in-CI cannot nest user namespaces, so relax that one knob; every other
# hardening default stays on.
kurly::render workloads/otel-collector/agent.libsonnet "+ k.hostUsers()" \
  | kubectl apply --namespace="$ns" --filename=-

# ---------------------------------------------------------------------------
# Assertion 1 — the config booted (a bad config never reaches Ready)
# ---------------------------------------------------------------------------

echo "== wait for the DaemonSet to become Ready =="
# The readiness probe is the health_check extension, so Ready means the collector
# started, parsed its config, and every pipeline came up.
if ! kubectl --namespace="$ns" rollout status daemonset/${app} --timeout=300s; then
  fail "otel-collector never became Ready — its rendered config was rejected at boot"
fi

echo "== assert: one collector pod per node =="
desired="$(kubectl --namespace="$ns" get daemonset/${app} -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null)"
ready="$(kubectl --namespace="$ns" get daemonset/${app} -o jsonpath='{.status.numberReady}' 2>/dev/null)"
echo "  desired=${desired} ready=${ready}"
[ -n "$ready" ] && [ "$ready" = "$desired" ] && [ "$ready" != "0" ] \
  || fail "the DaemonSet is not fully Ready (${ready}/${desired})"

# ---------------------------------------------------------------------------
# Assertion 2 — the OTLP receiver serves and the pipeline runs
# ---------------------------------------------------------------------------

echo "== a client pod to POST OTLP over HTTP =="
kubectl --namespace="$ns" run otlp-client --image=docker.io/library/busybox:1.37.0 \
  --restart=Never --command -- sleep 3600
kubectl --namespace="$ns" wait --for=condition=Ready pod/otlp-client --timeout=120s \
  || fail "the OTLP client pod never became Ready"

# The DaemonSet has no Service; reach the collector on its pod IP (one node, one
# pod). A minimal but VALID OTLP/HTTP trace: a 32-hex traceId, a 16-hex spanId.
pod_ip="$(kubectl --namespace="$ns" get pod --selector="app.kubernetes.io/name=${app}" \
  -o jsonpath='{.items[0].status.podIP}' 2>/dev/null)"
[ -n "$pod_ip" ] || fail "could not find the collector pod IP"
echo "  collector pod IP: ${pod_ip}"

trace='{"resourceSpans":[{"scopeSpans":[{"spans":[{"traceId":"5b8efff798038103d269b633813fc60c","spanId":"eee19b7ec3c1b174","name":"kurly-probe","kind":1,"startTimeUnixNano":"1","endTimeUnixNano":"2"}]}]}]}'

echo "== assert: the OTLP/HTTP receiver accepts a trace =="
# busybox wget exits non-zero on an HTTP error, so a clean exit is a 2xx — proof
# the otlp receiver is listening and accepted the span.
if ! kubectl --namespace="$ns" exec otlp-client -- \
  wget -q -O- --header='Content-Type: application/json' \
  --post-data="$trace" "http://${pod_ip}:4318/v1/traces" >/dev/null 2>&1; then
  fail "the collector rejected the OTLP/HTTP trace (receiver not listening or pipeline broken)"
fi
echo "  the collector accepted an OTLP/HTTP trace on :4318"

echo "== assert: the span reached the debug exporter =="
# The default pipeline ends at the debug exporter, which logs a line per batch;
# its appearance proves receive → memory_limiter → batch → export ran, not just
# that the socket answered.
saw=false
for _ in $(seq 1 20); do
  if kubectl --namespace="$ns" logs --selector="app.kubernetes.io/name=${app}" --tail=200 2>/dev/null \
    | grep -qiE 'Traces|"?spans"?'; then
    saw=true
    break
  fi
  sleep 3
done
[ "$saw" = true ] || fail "the trace never surfaced in the collector's debug exporter log"

echo "otel-collector served on a live cluster: the rendered config booted (Ready), and an OTLP/HTTP trace round-tripped receiver → pipeline → debug exporter"
