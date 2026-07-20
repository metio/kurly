# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# The Kubernetes static-analysis gate, weighted toward custom policy. Renders
# every example and workload, splits each into per-manifest files, then:
#   - conftest runs kurly's own invariants (policy/*.rego) over every manifest —
#     the primary gate, precise and free of ignore-list upkeep;
#   - pluto flags any removed or deprecated API version;
#   - kubesec scores the hardened workload controllers for security risk.
# kurly bakes in the hardened defaults these check, so its output passes and the
# gate guards that. The security-RELAXATION examples (legacy runs a baseline
# image, cron writes a scratch filesystem) exist to demonstrate the escape
# hatches, so they are exempt from the security SCORE — but still policy-checked.

# k8s-libsonnet floats at upstream HEAD; vendor it fresh so the gate checks what
# clusters actually run, and symlink the repo into the vendor tree so workloads
# resolve kurly's canonical import path the way JaaS does in-cluster.
jb install
mkdir -p vendor/github.com/metio
ln -sfn ../../.. vendor/github.com/metio/kurly

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
mandir="$workdir/manifests"
mkdir -p "$mandir"

# Examples render to a List directly; a workload stage is a composable app
# (function), rendered with defaults and wrapped in kurly.list like a consumer's
# JsonnetSnippet does. Each source is independent, so the whole set renders in
# parallel across cores — one more workload is one more parallel unit.
export MANDIR="$mandir"
render_one() {
  local src="$1" name
  name="$(printf '%s' "${src%.*}" | tr '/' '-')"
  case "$src" in
    workloads/*/*.libsonnet)
      jsonnet -J vendor -e "(import 'github.com/metio/kurly/main.libsonnet').list((import '$src')())" ;;
    *)
      jsonnet -J vendor "$src" ;;
  esac | jq -c '.items[]' | split --lines=1 --additional-suffix=.json - "$MANDIR/$name-"
}
export -f render_one
# shellcheck disable=SC2016
printf '%s\n' examples/*.jsonnet workloads/*/*.libsonnet | xargs -P"$(nproc)" -I{} bash -c 'render_one "$1"' _ {}
echo "rendered $(find "$mandir" -name '*.json' | wc -l) manifests"

echo "== conftest (kurly Rego invariants) =="
conftest test --policy policy "$mandir"/*.json

# The cross-manifest invariants read every rendered object at once (--combine),
# under their own namespace so the per-object rules above are unaffected. A
# ServiceMonitor pointed at a port no selected Service exposes is caught here and
# nowhere else — the workload's own config cannot see a port a consumer adds to
# the Service by hand.
echo "== conftest (cross-manifest invariants) =="
conftest test --combine --namespace combined --policy policy "$mandir"/*.json

# Prove that pass actually bites: a ServiceMonitor scraping a port no Service
# exposes must FAIL it. jsonnet has no try/catch and this is a render-time
# cluster fault, not a jsonnet assert, so the only way to observe the guard is to
# feed it a broken pair and require a non-zero exit.
echo "== the cross-manifest ServiceMonitor guard fires on a bad port =="
badpair="$(mktemp -d)"
trap 'rm -rf "$workdir" "$badpair"' EXIT
jsonnet -J vendor -e \
  "local k = import 'github.com/metio/kurly/main.libsonnet';
   k.list(k.http('probe', 'img:1') + k.serviceMonitor(port='nonexistent'))" \
  | jq -c '.items[]' | split --lines=1 --additional-suffix=.json - "$badpair/probe-"
if conftest test --combine --namespace combined --policy policy "$badpair"/*.json >/dev/null 2>&1; then
  echo "::error::cross-manifest guard passed a ServiceMonitor scraping a port no Service exposes" >&2
  exit 1
fi
echo "the guard fires on a ServiceMonitor whose port no Service exposes"

# Prove the no-Secret invariant bites too: a rendered Secret of any shape must
# FAIL the per-object policy. No workload authors one, so the only way to observe
# the guard is to feed it a Secret and require a non-zero exit.
echo "== the no-Secret guard fires on a rendered Secret =="
badsecret="$(mktemp -d)"
trap 'rm -rf "$workdir" "$badpair" "$badsecret"' EXIT
printf '{"apiVersion":"v1","kind":"Secret","metadata":{"name":"leaked"},"stringData":{"token":"hunter2"}}' \
  > "$badsecret/secret.json"
if conftest test --policy policy "$badsecret"/secret.json >/dev/null 2>&1; then
  echo "::error::no-Secret guard passed a rendered Secret" >&2
  exit 1
fi
echo "the guard fires on a rendered Secret"

echo "== pluto (removed / deprecated APIs) =="
pluto detect-files --directory "$mandir" --target-versions k8s=v1.31.0

echo "== kubesec (security score of the hardened controllers) =="
# The hardened examples score 7-11; a drop below this floor is a security
# regression (a missing readOnlyRootFilesystem / dropped-capabilities / seccomp).
# kubesec scans one manifest at a time and is the slowest step, so the scans run
# in parallel across cores — one more workload is one more parallel scan.
export THRESHOLD=6
score_one() {
  local manifest="$1" score
  case "$manifest" in
    *examples-legacy-* | *examples-cron-*) return 0 ;; # escape-hatch demos
    # spegel is node infrastructure: it serves the containerd content store to its
    # peers, so it runs as root with hostPath mounts (the socket is root-owned). No
    # score reaches the floor with hostPath present — the posture is hardened as far
    # as the job allows, and it is deployed to a namespace labelled for it.
    *workloads-spegel-*) return 0 ;;
  esac
  case "$(jq -r '.kind' "$manifest")" in
    Deployment | DaemonSet | CronJob | Pod) ;;
    *) return 0 ;;
  esac
  score="$(kubesec scan "$manifest" | jq -r '.[0].score')"
  if [ "$score" -lt "$THRESHOLD" ]; then
    echo "  FAIL $(basename "$manifest") scored $score (< $THRESHOLD)" >&2
    return 1
  fi
  echo "  ok   $(basename "$manifest") scored $score"
}
export -f score_one
# shellcheck disable=SC2016
if ! printf '%s\n' "$mandir"/*.json | xargs -P"$(nproc)" -I{} bash -c 'score_one "$1"' _ {}; then
  echo "kubesec: a hardened controller scored below $THRESHOLD" >&2
  exit 1
fi

echo "all security checks passed"
