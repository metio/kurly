# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Runs every step that turns an authored workload directory into a catalogued
# one, in the order the data actually flows. checklist.md is the prose; this is
# the part a machine can do.
#
#   onboard-workload <workload> [<workload>...]
#
#   NETWORK=0     skip the three registry sweeps (re-running after a stage edit,
#                 where the image has not moved and its facts still hold)
#   SKIP_VERIFY=1 stop before the full gate
#
# THE ORDER IS THE WHOLE POINT. Each generator reads what the previous one
# wrote, and running them in a plausible-looking order instead produces files
# that are individually fresh and collectively stale:
#
#   the registry ledgers  ->  catalog.json  ->  gen-maturity  ->  catalog.json
#                                                             ->  gen-smoke
#                                                             ->  gen-readme
#
# catalog.json is regenerated TWICE on purpose. gen-maturity derives the tiers
# from the evidence ledgers into catalog/maturity.gen.libsonnet, and catalog.json
# is built from that file — so the first render is what maturity reads and the
# second is what carries the tier. gen-smoke and gen-readme both read
# catalog.json and neither notices being handed an old one: gen-readme silently
# writes one README fewer, which reads exactly like success.
set -uo pipefail

[ "$#" -gt 0 ] || { echo "usage: onboard-workload <workload> [<workload>...]" >&2; exit 2; }

catalog=catalog/catalog.json
failed=0

# A workload's stage keys, from the files it actually holds — the same shape the
# subset variables of the registry sweeps take.
stages_of() {
  local w="$1" f st
  for f in "workloads/${w}"/*.libsonnet; do
    [ -e "$f" ] || continue
    st="$(basename "$f" .libsonnet)"
    printf '%s/%s\n' "$w" "$st"
  done
}

# Refuses on what a later step would otherwise fail on obscurely, or worse, skip
# in silence.
preflight() {
  local w="$1" ok=0 key f
  if [ ! -d "workloads/${w}" ]; then
    echo "::error::workloads/${w} does not exist" >&2
    return 1
  fi
  # A workload directory is a released unit and its tag is <name>-<version>, so
  # these two names would collide with the library's and the catalog's tags.
  case "$w" in
    library | catalog)
      echo "::error::a workload may not be named '${w}' — it collides with the ${w} release tag prefix" >&2
      return 1
      ;;
  esac
  [ -f "workloads/${w}/version.txt" ] || {
    echo "::error::workloads/${w}/version.txt is missing (commit it as the literal text 'dev')" >&2
    ok=1
  }
  while IFS= read -r key; do
    f="workloads/${key}.image"
    [ -f "$f" ] || { echo "::error::${f} is missing — a stage pins its own image, by digest" >&2; ok=1; continue; }
    # gen-architectures and gen-signatures enumerate with `git ls-files`, so an
    # UNTRACKED .image is invisible to them: the sweep runs, reports the stages
    # it knew about, and never mentions the one being onboarded. gen-smoke then
    # writes no scenario for it, because it only writes for stages whose
    # architectures are known. Nothing anywhere fails. Registering the path with
    # the index (no content staged) is what makes the sweeps see it.
    if ! git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
      git add --intent-to-add "$f" >/dev/null 2>&1 \
        && echo "  registered ${f} with the index so the registry sweeps can see it"
    fi
    # The import map cannot be globbed — jsonnet has no filesystem access — so a
    # stage that is not named there is simply absent from the catalogue, and the
    # reconcile assert only fires once the annotation names it too.
    grep -q "'${key}': import" catalog/catalog.jsonnet || {
      echo "::error::catalog/catalog.jsonnet does not import '${key}' — add:" >&2
      echo "    '${key}': import 'github.com/metio/kurly/workloads/${key}.libsonnet'," >&2
      ok=1
    }
  done < <(stages_of "$w")
  grep -q "^    ${w}: {" catalog/annotations.libsonnet || {
    echo "::error::catalog/annotations.libsonnet has no entry for ${w} (category is mandatory)" >&2
    ok=1
  }
  return "$ok"
}

# catalog.json, regenerated from the annotations and every ledger. Guarded rather
# than redirected: `jsonnet > catalog.json` truncates the file before it knows
# whether the render succeeds, so one broken annotation replaces the catalogue
# with an empty file and every gate downstream then measures nothing.
regen_catalog() {
  local tmp
  tmp="$(mktemp)"
  if ! jsonnet -J vendor catalog/catalog.jsonnet >"$tmp" 2>/dev/null; then
    echo "::error::catalog/catalog.jsonnet does not render — catalog.json left untouched" >&2
    jsonnet -J vendor catalog/catalog.jsonnet >/dev/null || true
    rm -f "$tmp"
    return 1
  fi
  if ! jq -e '.workloads | length > 0' "$tmp" >/dev/null 2>&1; then
    echo "::error::the regenerated catalogue holds no workloads — catalog.json left untouched" >&2
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$catalog"
}

[ -d vendor ] || jb install >/dev/null 2>&1

echo "==> preflight"
targets=()
for w in "$@"; do
  if preflight "$w"; then targets+=("$w"); else failed=1; fi
done
[ "${#targets[@]}" -gt 0 ] || { echo "nothing to onboard" >&2; exit 1; }

stage_keys=""
for w in "${targets[@]}"; do
  while IFS= read -r key; do stage_keys="${stage_keys}${key} "; done < <(stages_of "$w")
done
echo "    stages: ${stage_keys}"

# The stage renders, follows its name, survives kurly.mirror, and holds the rest
# of the per-stage contract. Before the sweeps, because a stage that does not
# render has nothing worth asking a registry about.
echo "==> check-tests"
check-tests >/dev/null || { echo "::error::check-tests failed — run it directly for the detail" >&2; exit 1; }
echo "    ok"

if [ "${NETWORK:-1}" = 1 ]; then
  # Subset to the stages being onboarded. A full sweep re-asks three hundred
  # registries for facts it already holds, which is what exhausts a rate limit
  # before reaching the one stage that needed asking.
  echo "==> gen-architectures (${stage_keys})"
  STAGES="$stage_keys" gen-architectures >/dev/null || failed=1
  echo "==> gen-upstream (${targets[*]})"
  WORKLOADS="${targets[*]}" gen-upstream || failed=1
  echo "==> gen-signatures (${stage_keys})"
  STAGES="$stage_keys" gen-signatures >/dev/null || failed=1
else
  echo "==> registry sweeps skipped (NETWORK=0)"
fi

echo "==> catalog.json"
regen_catalog || exit 1
echo "==> gen-maturity"
gen-maturity >/dev/null || failed=1
echo "==> catalog.json (again — it carries what gen-maturity just derived)"
regen_catalog || exit 1
echo "==> gen-smoke"
gen-smoke >/dev/null || failed=1
echo "==> gen-readme"
gen-readme >/dev/null || failed=1

# Say what was actually produced, per workload, rather than reporting a tidy
# success: every one of these can come out absent, and absent is the answer that
# looks like nothing went wrong.
echo
echo "==> what the catalogue now holds"
for w in "${targets[@]}"; do
  jq -r --arg w "$w" '
    .workloads[] | select(.id == $w)
    | "  \(.id)  [\(.category)]  \(.maturity.tier)"
      + "\n    license:   \(.license // "ABSENT")"
      + "\n    upstream:  \(.upstream.repo // "ABSENT")"
      + (
          [ .stages[]
            | "\n    \(.id): arches=\(if .architectures then (.architectures | join(",")) else "ABSENT" end)"
              + " pvcs=\(.storage.pvcs)"
              + " pss=\(.pss.level // "null")"
              + " signed=\(if .signature == null then "ABSENT" else (.signature.signed | tostring) end)"
              + " secretKeys=\((.secretKeys // []) | length)"
          ] | add // ""
        )
  ' "$catalog" 2>/dev/null || echo "  ${w}: NOT IN THE CATALOGUE"
  if [ -f "hack/smoke/scenario-${w}.sh" ]; then
    echo "    scenario:  hack/smoke/scenario-${w}.sh"
  else
    echo "    scenario:  NONE — gen-smoke writes one only once the architectures are known"
  fi
done

echo
echo "==> check-catalog"
if check-catalog >/dev/null 2>&1; then
  echo "    ok"
else
  echo "::error::check-catalog failed — run it directly for the drift" >&2
  failed=1
fi

if [ "${SKIP_VERIFY:-0}" = 0 ]; then
  echo "==> verify (the full gate)"
  verify || failed=1
fi

echo
echo "still to do by hand — neither is derivable, and both are ABSENT until somebody does them:"
for w in "${targets[@]}"; do
  echo "  bash hack/smoke/scenario-${w}.sh    # boot it, then record the date in catalog/e2e-verified.libsonnet"
done
echo "  bash hack/trademark-probe.sh <name>   # then READ what it finds; posture + policy URL together"

exit "$failed"
