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
# clusters actually run.
jb install

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
mandir="$workdir/manifests"
mkdir -p "$mandir"

for source in examples/*.jsonnet workloads/*/stages.jsonnet; do
  name="$(printf '%s' "${source%.jsonnet}" | tr '/' '-')"
  rendered="$workdir/$name.rendered.json"
  jsonnet -J vendor "$source" > "$rendered"
  if [ "$(jq -r 'if .kind == "List" then "list" else "stagemap" end' "$rendered")" = "list" ]; then
    jq -c '.items[]' "$rendered" \
      | split --lines=1 --additional-suffix=.json - "$mandir/$name-"
  else
    for stage in $(jq -r 'keys[]' "$rendered"); do
      jq -c --arg stage "$stage" '.[$stage].items[]' "$rendered" \
        | split --lines=1 --additional-suffix=.json - "$mandir/$name-$stage-"
    done
  fi
done
echo "rendered $(find "$mandir" -name '*.json' | wc -l) manifests"

echo "== conftest (kurly Rego invariants) =="
conftest test --policy policy "$mandir"/*.json

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
