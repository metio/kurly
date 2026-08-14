# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Asks deps.dev what the OpenSSF Scorecard says about each workload's UPSTREAM
# PROJECT, and writes the answers to catalog/scorecard.gen.libsonnet.
#
# THIS IS A FACT ABOUT THE PROJECT, NOT ABOUT THE IMAGE KURLY PINS, and that
# distinction is the reason it is a separate field rather than folded in with the
# others. `pss`, `posture` and `bsi` describe the manifest kurly renders;
# `signature` describes the specific bytes of a pinned image. A Scorecard score
# describes how the software is DEVELOPED — whether releases are signed, whether
# dependencies are pinned, whether a branch is protected, whether anybody has
# touched it lately. A consumer weighing "should we host this for a tenant" wants
# both halves and must not mistake one for the other.
#
# The score is anchored to what was measured: the date Scorecard ran and the
# commit it ran against are recorded beside it. Unlike a signature, the claim does
# not go stale the moment an image is bumped — it is about the repository — but a
# score from a year ago is a different statement from one from last week, so the
# date is published rather than hidden.
#
# THE LICENCE DEPS.DEV REPORTS IS DELIBERATELY IGNORED. kurly already derives the
# licence twice — from the image's own OCI label and from the project's forge —
# and a third source would only mean a third answer to reconcile. Ask this for
# what nothing else can answer.
#
# An absent entry means NOT ASKED, or a forge deps.dev does not index (it knows
# GitHub, GitLab and Bitbucket; the catalogue also carries Codeberg and a handful
# of self-hosted forges). It never means a bad score.
#
# Network-bound, like gen-forge and gen-architectures: run on demand or on a
# schedule, never in the per-PR gate.
set -euo pipefail

# The workload glob below expands in the shell's collation order, and a locale
# that ignores punctuation orders `calibre-web` after `calibre` where C orders it
# before — which would make the generated file differ between a contributor's
# machine and CI while saying the same thing.
export LC_ALL=C

# .build/catalog.json is a BUILD ARTIFACT with no committed copy, so a fresh
# checkout does not have one. Producing it here means this depends on the DATA it
# needs rather than on somebody having remembered to render it first.
[ -f .build/catalog.json ] || gen-catalog >/dev/null

only="${WORKLOADS:-}"
out=catalog/scorecard.gen.libsonnet
# Written progressively next to the output: a sweep over five hundred projects is
# measured in minutes, and a run interrupted near the end must not throw away its
# answers. The next run reads whatever is here and resumes.
tmp="${out}.partial"
previous="$(mktemp)"
partial="$(mktemp --suffix=.libsonnet)"
trap 'rm -f "$previous" "$partial"' EXIT

closePartial() {
  [ -f "$tmp" ] || return 1
  cat "$tmp" > "$partial"
  printf '}\n' >> "$partial"
  jsonnet "$partial" 2>/dev/null
}

{
  if [ -f "$out" ]; then jsonnet "$out" 2>/dev/null || echo '{}'; else echo '{}'; fi
  closePartial || echo '{}'
} | jq --slurp '.[0] * .[1]' > "$previous"

answered_already=""
if [ -f "$tmp" ]; then
  answered_already="$(closePartial | jq --raw-output 'keys[]' 2>/dev/null | paste -sd' ' - || true)"
  [ -z "$answered_already" ] || echo "resuming: $(wc -w <<<"$answered_already") workloads already answered by the interrupted run" >&2
fi

# One project, answered by deps.dev. Emits a JSON object; an empty one means it
# did not answer, which is different from answering that it does not know the
# project.
ask() {
  local url="$1" key="" body=""
  case "$url" in
    https://github.com/*) key="github.com/${url#https://github.com/}" ;;
    https://gitlab.com/*) key="gitlab.com/${url#https://gitlab.com/}" ;;
    https://bitbucket.org/*) key="bitbucket.org/${url#https://bitbucket.org/}" ;;
    # Every other forge — Codeberg, a self-hosted Forgejo, SourceForge — is not
    # indexed there. Left unasked rather than asked and misreported.
    *) return 0 ;;
  esac
  key="${key%/}"
  key="${key%.git}"
  body="$(curl --silent --show-error --location --max-time 30 \
    "https://api.deps.dev/v3alpha/projects/${key//\//%2F}" 2>/dev/null || true)"
  # A project deps.dev has never seen answers 404 with an error object; a project
  # it knows but Scorecard has not run against answers 200 with no scorecard.
  # Only the second is worth recording, and neither is a failure.
  jq --exit-status '.projectKey.id' >/dev/null 2>&1 <<<"$body" || return 0
  jq --compact-output '
    if .scorecard == null then {} else {
      repo: .projectKey.id,
      score: .scorecard.overallScore,
      date: (.scorecard.date | split("T")[0]),
      commit: .scorecard.repository.commit,
      stars: .starsCount,
      checks: (reduce (.scorecard.checks[]? | select(.score >= 0)) as $c ({}; . + { ($c.name): $c.score })),
    } end' <<<"$body"
}

targets="$(jq --raw-output '.workloads[] | select(.upstream.repo != null) | "\(.id)\t\(.upstream.repo)"' .build/catalog.json | LC_ALL=C sort)"
[ -z "$only" ] || targets="$(printf '%s\n' "$targets" | grep -E "^($(printf '%s\n' "$only" | tr ' ' '|'))	" || true)"

[ -f "$tmp" ] || {
  printf '// %s: The kurly Authors\n' 'SPDX-FileCopyrightText'
  printf '// %s: 0BSD\n\n' 'SPDX-License-Identifier'
  printf '// Generated by scripts/gen-scorecard.sh from deps.dev — do not edit;\n'
  printf '// regenerate with: gen-scorecard\n'
  printf '//\n'
  printf '// What the OpenSSF Scorecard says about each workload UPSTREAM PROJECT: the\n'
  printf '// overall score, the per-check scores behind it, and the date and commit the\n'
  printf '// scan ran against. A fact about how the software is DEVELOPED, not about the\n'
  printf '// image kurly pins or the manifest it renders.\n'
  printf '//\n'
  printf '// Absent means not asked, or a forge deps.dev does not index. Never a bad score.\n'
  printf '{\n'
} > "$tmp"

asked=0
answered=0
while IFS=$'\t' read -r id repo; do
  [ -n "$id" ] || continue
  case " $answered_already " in *" $id "*) continue ;; esac
  asked=$((asked + 1))
  result="$(ask "$repo" || true)"
  if [ -n "$result" ] && [ "$result" != "{}" ]; then
    printf "  '%s': %s,\n" "$id" "$(jq --compact-output 'to_entries|map("\(.key): \(.value|tojson)")|join(", ")|"{ " + . + " }"' <<<"$result" | jq --raw-output .)" >> "$tmp"
    answered=$((answered + 1))
  fi
done <<<"$targets"

printf '}\n' >> "$tmp"
mv "$tmp" "$out"
jsonnetfmt --in-place "$out"

echo "wrote ${out}: asked ${asked} projects, ${answered} answered with a Scorecard"
