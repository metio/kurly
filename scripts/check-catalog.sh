# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# The catalog gate: regenerate .build/catalog.json from the library annotations
# and fail if the committed copy is stale. Rendering it also runs the drift
# asserts in catalog.jsonnet (a feature exported without an annotation, or an
# annotation with no matching export, fails here) — so the machine-readable API
# model the assembler reads can never silently disagree with the library.

# The derived maturity tiers (catalog/maturity.gen.libsonnet) must match what the
# repository actually proves. Regenerate from the live signals and fail if the
# committed file is stale — the same discipline the catalog itself follows, so a
# workload can never claim a tier the smoke scenarios and tests do not back.
gen-maturity >/dev/null
if ! git diff --quiet -- catalog/maturity.gen.libsonnet 2>/dev/null; then
  echo "catalog/maturity.gen.libsonnet is stale — regenerate it:" >&2
  echo "  gen-maturity" >&2
  echo >&2
  git --no-pager diff -- catalog/maturity.gen.libsonnet >&2 || true
  exit 1
fi
echo "maturity tiers match the smoke scenarios and tests"

# The SPDX register every licence value is checked against comes from the
# devShell, so it moves when the flake pin moves. Rewrite it and fail if the
# committed copy is stale, exactly as the maturity tiers are handled — a
# licence that was valid against last year's list must not stay published as
# valid against this one's.
gen-spdx >/dev/null
if ! git diff --quiet -- catalog/spdx.gen.libsonnet 2>/dev/null; then
  echo "catalog/spdx.gen.libsonnet is stale — regenerate it:" >&2
  echo "  gen-spdx" >&2
  echo >&2
  git --no-pager diff --stat -- catalog/spdx.gen.libsonnet >&2 || true
  exit 1
fi
echo "the SPDX register matches the one the devShell ships"

# The catalogue drops a licence label SPDX does not recognise rather than
# publishing it, which is right but silent. Name them here so a junk label stays
# visible: each one is a workload whose licence nobody knows yet, and the fix is
# to read the project's own LICENSE and annotate what it says.
unknown="$(jsonnet -e '
  local spdx = import "catalog/spdx.gen.libsonnet";
  local upstream = import "catalog/upstream.gen.libsonnet";
  std.join(" ", [
    "%s=%s" % [w, upstream[w].license]
    for w in std.objectFields(upstream)
    if std.objectHas(upstream[w], "license")
       && upstream[w].license != "NOASSERTION"
       && !std.all([
         std.objectHas(spdx, std.rstripChars(std.stripChars(t, "()"), "+"))
         for t in std.split(upstream[w].license, " ")
         if !std.member(["AND", "OR", "WITH"], t) && std.stripChars(t, "()") != ""
       ])
  ])' | jq -r)"
if [ -n "$unknown" ]; then
  echo "image labels stating a licence SPDX does not know (dropped, not published): ${unknown}"
fi

# The generator imports the library, which imports k8s-libsonnet; vendor it.
[ "${KURLY_VENDORED:-}" = "1" ] || jb install

# The workloads section imports each stage by kurly's canonical path
# (github.com/metio/kurly/...); resolve it locally by symlinking the repo into
# the vendor tree, exactly as check-examples does.
mkdir -p vendor/github.com/metio
ln -sfn ../../.. vendor/github.com/metio/kurly

# Rendering it IS the gate. catalog.jsonnet is dense with asserts — a feature
# exported without an annotation, a stage whose import and key disagree, a
# generated ledger naming a stage that no longer exists — and every one of them
# fails here.
#
# What this no longer does is compare the result against a committed copy. The
# file is a build artifact now, gitignored and regenerated wherever it is needed,
# so there is nothing to be stale against: a diff would only ever report that
# somebody had not run the generator, which is not a fact about the library.
# Every d.T.<name> must be a type docs.libsonnet actually defines. Jsonnet does
# catch an invented one — but as `Field does not exist: number`, pointing at
# docs.libsonnet rather than at the annotation that wrote it, which is a slow way
# to find a typo in a nine-thousand-line file. `number` has been written three
# times where the type is `int`.
# From the T:: block ALONE — docs.libsonnet has other objects whose fields would
# otherwise be offered as types (`help`, `required`, `default`), which is worse
# than no suggestion because each one parses and none is a type.
known="$(sed -n '/^  T:: {/,/^  },/p' catalog/docs.libsonnet | grep -oE '^    [a-z]+:' | tr -d ' :' | sort -u)"
bad=0
while IFS=: read -r file line type; do
  grep -qx "$type" <<<"$known" && continue
  echo "::error::${file}:${line}: d.T.${type} is not a docsonnet type — one of: $(tr '\n' ' ' <<<"$known")" >&2
  bad=1
done < <(grep -noE 'd\.T\.[a-zA-Z]+' catalog/annotations.libsonnet | sed 's/^\([0-9]*\):d\.T\./catalog\/annotations.libsonnet:\1:/')
[ "$bad" = 0 ] || exit 1

mkdir -p .build
if ! jsonnet -J vendor catalog/catalog.jsonnet > .build/catalog.json.check; then
  rm -f .build/catalog.json.check
  echo "::error::catalog/catalog.jsonnet does not render" >&2
  exit 1
fi
mv .build/catalog.json.check .build/catalog.json
echo "catalog renders, and its asserts hold"

# The catalog claims to be the machine-readable model of kurly's public API — the
# Assembler builds snippets from it and the Reference site renders it — and
# catalog.jsonnet already fails when a FEATURE is exported without an annotation.
# A workload stage's PARAMETERS had no such check, and drifted: 27 of them went
# undocumented, including every knob added to cnpg-cluster for storage, placement
# and pull secrets. A parameter the catalog omits is a parameter nobody can find,
# which makes it a private API however well it works.
#
# jsonnet cannot introspect a function's parameters, so the signature is read
# from the source. That is reliable precisely because check-fmt enforces the
# layout: jsonnetfmt puts one parameter per line, indented two spaces.
echo "== every workload parameter is annotated =="
# Every workload's parameters by default; just the changed ones when
# KURLY_WORKLOADS narrows an incremental run. The catalog reconcile above is
# library-wide and always runs; only this per-workload parameter sweep narrows.
if [ -n "${KURLY_WORKLOADS:-}" ]; then
  mapfile -t param_stages <<<"$KURLY_WORKLOADS"
else
  param_stages=(workloads/*/*.libsonnet)
fi
fail=0

# The import map in catalog.jsonnet names each stage twice — once as the key the
# rest of the catalog looks it up by, once as the literal path jsonnet imports.
# jsonnet cannot compare them, because an import evaluates to the imported object
# and the path it came from is gone by the time anything could look. A key that
# named a different stage's file would render one stage's facts under another
# stage's name, and every derived value beside it would be quietly about the wrong
# workload. So the two halves of each line are compared here, where they are still
# text.
while IFS= read -r line; do
  key="$(sed -E "s/^ *'?([^':]+)'?: import .*/\1/" <<<"$line")"
  path="$(sed -E "s/.*import 'github\.com\/metio\/kurly\/workloads\/(.+)\.libsonnet'.*/\1/" <<<"$line")"
  if [ "$key" != "$path" ]; then
    echo "::error::catalog.jsonnet: stage '${key}' imports workloads/${path}.libsonnet — the key and the path name different stages" >&2
    fail=1
  fi
done < <(grep -E "^  '?[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+'?: import 'github\.com/metio/kurly/workloads/" catalog/catalog.jsonnet)
[ "$fail" -eq 0 ] && echo "every stage import is keyed by the file it imports"

for stage in "${param_stages[@]}"; do
  workload="$(basename "$(dirname "$stage")")"
  id="$(basename "$stage" .libsonnet)"

  # Order is checked so the Reference site and the Assembler present a stage's
  # parameters as its signature declares them; a reader comparing the two should
  # not have to reconcile a shuffle. It is no longer a correctness matter — every
  # generated call names its arguments, so binding does not depend on order —
  # which is exactly why it is worth keeping cheap and stated plainly rather than
  # dressed up as a safety check.
  actual="$(sed -n '/^function(/,/^)/p' "$stage" | grep -oE '^  [a-zA-Z][a-zA-Z0-9]*=' | tr -d ' =')"
  documented="$(jq -r --arg w "$workload" --arg s "$id" \
    '.workloads[] | select(.id == $w) | .stages[] | select(.id == $s) | .args[]?.name' .build/catalog.json)"

  missing="$(comm -23 <(printf '%s\n' "$actual" | sort -u) <(printf '%s\n' "$documented" | sort -u) | tr '\n' ' ')"
  stale="$(comm -13 <(printf '%s\n' "$actual" | sort -u) <(printf '%s\n' "$documented" | sort -u) | tr '\n' ' ')"
  if [ -n "${missing// /}" ]; then
    echo "::error::${stage}: parameter(s) not annotated in catalog/annotations.libsonnet: ${missing}" >&2
    fail=1
  elif [ -n "${stale// /}" ]; then
    echo "::error::${stage}: annotated parameter(s) the function does not take: ${stale}" >&2
    fail=1
  elif [ "$actual" != "$documented" ]; then
    echo "::error::${stage}: annotated parameters are in a different order than the function declares them —" >&2
    echo "  function: $(printf '%s' "$actual" | tr '\n' ' ')" >&2
    echo "  catalog:  $(printf '%s' "$documented" | tr '\n' ' ')" >&2
    fail=1
  else
    echo "every parameter annotated, in order: $stage"
  fi

  # And that each annotated DEFAULT is the one the function actually declares.
  # The catalog cannot derive this — jsonnet gives no way to read a function's
  # parameter defaults — so the annotation states them by hand, which makes it a
  # transcription of a fact that lives somewhere else. Left ungated it drifts
  # silently and stays confident: the published default for cassandra-cluster was
  # a whole major behind what the stage deploys, and a consumer prefilling a form
  # from the catalog would have offered it.
  #
  # Only simple literals are compared — a quoted string, a number, a boolean. A
  # computed default has no single value to state and the annotation does not
  # claim one.
  while IFS= read -r decl; do
    [ -n "$decl" ] || continue
    pname="${decl%%=*}"
    pval="${decl#*=}"
    pval="${pval%,}"
    case "$pval" in
      "'"*"'") pval="${pval#\'}"; pval="${pval%\'}" ;;
      [0-9]* | true | false) : ;;
      *) continue ;;
    esac
    annotated="$(jq -r --arg w "$workload" --arg s "$id" --arg n "$pname" \
      '.workloads[] | select(.id == $w) | .stages[] | select(.id == $s) | .args[]?
       | select(.name == $n) | if has("default") then (.default | tostring) else empty end' \
      .build/catalog.json)"
    # No annotated default is a fair statement about a parameter; a WRONG one is not.
    [ -n "$annotated" ] || continue
    if [ "$annotated" != "$pval" ]; then
      echo "::error::${stage}: ${pname} defaults to '${pval}' but the catalog publishes '${annotated}' — fix catalog/annotations.libsonnet" >&2
      fail=1
    fi
  done < <(sed -n '/^function(/,/^)/p' "$stage" \
    | grep -oE "^  [a-zA-Z][a-zA-Z0-9]*=('[^']*'|[0-9][0-9.]*|true|false)," | sed 's/^  //')
done
[ "$fail" -eq 0 ] || exit 1
