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
# JsonnetSnippet does.
render() {
  local src="$1"
  case "$src" in
    workloads/*/*.libsonnet)
      jsonnet -J vendor -e "(import 'github.com/metio/kurly/main.libsonnet').list((import '$src')())" ;;
    *)
      jsonnet -J vendor "$src" ;;
  esac
}

for source in examples/*.jsonnet workloads/*/*.libsonnet; do
  name="$(printf '%s' "${source%.*}" | tr '/' '-')"
  render "$source" \
    | jq -c '.items[]' \
    | split --lines=1 --additional-suffix=.json - "$mandir/$name-"
done
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

echo "== pluto (removed / deprecated APIs) =="
pluto detect-files --directory "$mandir" --target-versions k8s=v1.31.0

echo "== kubesec (security score of the hardened controllers) =="
# The hardened examples score 7-11; a drop below this floor is a security
# regression (a missing readOnlyRootFilesystem / dropped-capabilities / seccomp).
threshold=6
kubesec_failed=0
for manifest in "$mandir"/*.json; do
  case "$manifest" in
    *examples-legacy-* | *examples-cron-*) continue ;; # escape-hatch demos
  esac
  case "$(jq -r '.kind' "$manifest")" in
    Deployment | DaemonSet | CronJob | Pod) ;;
    *) continue ;;
  esac
  score="$(kubesec scan "$manifest" | jq -r '.[0].score')"
  if [ "$score" -lt "$threshold" ]; then
    echo "  FAIL $(basename "$manifest") scored $score (< $threshold)" >&2
    kubesec_failed=1
  else
    echo "  ok   $(basename "$manifest") scored $score"
  fi
done
if [ "$kubesec_failed" -ne 0 ]; then
  echo "kubesec: a hardened controller scored below $threshold" >&2
  exit 1
fi

echo "all security checks passed"
