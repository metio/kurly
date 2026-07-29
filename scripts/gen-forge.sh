# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Asks each workload's upstream forge what the project is called and which
# licence it publishes under, into catalog/forge.gen.libsonnet.
#
# Why the forge rather than the image: an image label states what its build
# pipeline was told, which is the packager's reading of the licence, second-hand
# and often absent. A forge reads the project's own LICENSE file and resolves it
# to an SPDX identifier — the same file a lawyer would read, and the same answer
# it would give tomorrow. That makes the licence DERIVED, so it is rechecked on a
# schedule rather than transcribed once and trusted forever; a project that
# relicenses shows up as a diff instead of as a claim that quietly went stale.
#
# The upstream repository itself is not derivable this way — it is read from
# catalog.json, where it is either derived from the image's source label or
# stated in catalog/annotations.libsonnet by someone who established it. That is
# the one fact here a person supplies; everything hanging off it is asked, not
# assumed.
#
# Network-bound, like gen-upstream and gen-architectures: run on demand or on a
# schedule, never in the per-PR gate. Unauthenticated, GitHub answers sixty
# requests an hour, so a full sweep takes hours; export GITHUB_TOKEN (any
# read-only token, and CI's own `github.token` will do) and it takes a minute.
#
# WORKLOADS (space-separated ids) narrows the sweep, keeping what the last run
# derived for the rest.
set -euo pipefail

only="${WORKLOADS:-}"
out=catalog/forge.gen.libsonnet
# Written progressively next to the output: a rate-limited sweep is measured in
# hours, and a run interrupted near the end must not throw away its answers. The
# next run reads whatever is here as already-derived and resumes.
tmp="${out}.partial"
previous="$(mktemp)"
# The partial file is a Jsonnet object with its closing brace still missing, so
# it is closed into a real file to be read. Not a process substitution: jsonnet
# reopens the path it is given, and /dev/fd/N is already at end of file by then,
# so it fails to parse — silently, since a failure here reads as "nothing was
# derived before".
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

# A leftover partial file means the last run was interrupted, so this one
# resumes it: whatever that run already asked is kept unasked, and the sweep
# picks up where it stopped. Without this a crash at workload 280 would cost
# another five hours to learn what it already knew. A run that starts with no
# partial file asks everything, which is what makes this a refresh rather than a
# cache — the point of the generator is that a relicensing shows up as a diff.
answered_already=""
if [ -f "$tmp" ]; then
  answered_already="$(closePartial | jq --raw-output 'keys[]' 2>/dev/null | paste -sd' ' - || true)"
  [ -z "$answered_already" ] || echo "resuming: $(wc -w <<<"$answered_already") workloads already answered by the interrupted run" >&2
fi

auth=()
[ -n "${GITHUB_TOKEN:-}" ] && auth=(--header "Authorization: Bearer ${GITHUB_TOKEN}")
# Unauthenticated GitHub allows sixty requests an hour. Pace to just under that
# rather than sprinting into a wall and calling the resulting errors "unknown".
pause=$([ -n "${GITHUB_TOKEN:-}" ] && echo 0 || echo 61)

# One repository, answered by its forge. Emits a JSON object with whatever the
# forge knew; an empty object means it did not answer at all, which is different
# from answering that it does not know.
ask() {
  local url="$1" body=""
  case "$url" in
    https://github.com/*)
      local path="${url#https://github.com/}"
      body="$(curl --silent --show-error --location --max-time 30 \
        --header 'Accept: application/vnd.github+json' "${auth[@]}" \
        "https://api.github.com/repos/${path}" 2>/dev/null || true)"
      # A rate limit and a missing repository both arrive as an object with a
      # message; only the second is an answer, and conflating them would delete
      # a licence every time the limit is hit.
      if jq --exit-status '.id' >/dev/null 2>&1 <<<"$body"; then
        jq --compact-output '{
          license: (if (.license.spdx_id // "") | test("^(NOASSERTION|)$") then null else .license.spdx_id end),
          name: .name,
          homepage: (if (.homepage // "") == "" then null else .homepage end),
          archived: .archived,
        }' <<<"$body"
      elif jq --exit-status 'select(.message == "Not Found")' >/dev/null 2>&1 <<<"$body"; then
        echo '{"gone": true}'
      else
        echo '{}'
      fi
      ;;
    https://gitlab.com/*)
      local path="${url#https://gitlab.com/}"
      # GitLab reports the licence only when asked for it, and wants the project
      # path URL-encoded as one segment.
      body="$(curl --silent --location --max-time 30 \
        "https://gitlab.com/api/v4/projects/${path//\//%2F}?license=true" 2>/dev/null || true)"
      if jq --exit-status '.id' >/dev/null 2>&1 <<<"$body"; then
        jq --compact-output '{
          license: (.license.nickname // .license.key // null),
          name: .name,
          homepage: null,
          archived: .archived,
        }' <<<"$body"
      else
        echo '{}'
      fi
      ;;
    *)
      # Codeberg, self-hosted Gitea/Forgejo and the rest: their API serves the
      # LICENSE file but does not say which licence it is, and classifying the
      # text would be a guess wearing a derivation's clothes. Reported as not
      # asked, which is not the same as asked and unanswered.
      echo '{"unasked": true}'
      ;;
  esac
}

repos="$(jq --raw-output '.workloads[] | select(.upstream.repo) | "\(.id)\t\(.upstream.repo)"' catalog/catalog.json)"
count="$(wc -l <<<"$repos")"

{
  printf '// %s: The kurly Authors\n' 'SPDX-FileCopyrightText'
  printf '// %s: 0BSD\n\n' 'SPDX-License-Identifier'
  printf '// Generated by scripts/gen-forge.sh from each upstream repository —\n'
  printf '// do not edit; regenerate with: gen-forge\n'
  printf '//\n'
  printf "// What the project's own forge says about it: the licence it detected in the\n"
  printf '// repository, the name the repository carries, and whether it is archived. A\n'
  printf "// workload's annotation overrides anything here; see catalog/annotations.libsonnet.\n"
  printf '{\n'
} > "$tmp"

total=0
answered=0
kept=""
unanswered=""
unasked=""
while IFS=$'\t' read -r id url; do
  [ -n "$id" ] || continue
  total=$((total + 1))

  keep() {
    local entry
    entry="$(jq --compact-output --arg id "$id" '.[$id] // empty' "$previous")"
    [ -n "$entry" ] || return 0
    answered=$((answered + 1))
    {
      printf "  '%s': {\n" "$id"
      jq --raw-output 'to_entries[] | if (.value | type) == "boolean" then "    \(.key): \(.value)," else "    \(.key): '"'"'\(.value)'"'"'," end' <<<"$entry"
      printf '  },\n'
    } >> "$tmp"
  }

  if [ -n "$only" ] && ! grep -qw -- "$id" <<<"$only"; then
    keep
    continue
  fi
  if [ -n "$answered_already" ] && grep -qw -- "$id" <<<"$answered_already"; then
    keep
    continue
  fi

  [ "$total" = 1 ] || [ "$pause" = 0 ] || sleep "$pause"
  reply="$(ask "$url")"

  if jq --exit-status '.unasked // false' >/dev/null 2>&1 <<<"$reply"; then
    printf '%3d/%-3d %-28s not asked: %s reports no licence\n' "$total" "$count" "$id" \
      "$(sed -E 's|https://([^/]+)/.*|\1|' <<<"$url")" >&2
    unasked="${unasked}${id} "
    keep
    continue
  fi

  if [ "$reply" = '{}' ]; then
    printf '%3d/%-3d %-28s no answer\n' "$total" "$count" "$id" >&2
    kept="${kept}${id} "
    keep
    continue
  fi

  license="$(jq --raw-output '.license // empty' <<<"$reply")"
  name="$(jq --raw-output '.name // empty' <<<"$reply")"
  homepage="$(jq --raw-output '.homepage // empty' <<<"$reply")"
  archived="$(jq --raw-output '.archived // false' <<<"$reply")"
  gone="$(jq --raw-output '.gone // false' <<<"$reply")"

  if [ "$gone" = true ]; then
    # The repository does not exist. That is an answer, and a useful one: the
    # upstream URL is wrong or the project moved, and the fix is to correct it.
    printf '%3d/%-3d %-28s gone: %s\n' "$total" "$count" "$id" "$url" >&2
    unanswered="${unanswered}${id} "
    continue
  fi

  printf '%3d/%-3d %-28s %s%s\n' "$total" "$count" "$id" \
    "${license:-no licence detected}" "$([ "$archived" = true ] && printf ' (archived)')" >&2
  answered=$((answered + 1))
  {
    printf "  '%s': {\n" "$id"
    [ -n "$license" ] && printf "    license: '%s',\n" "$license"
    [ -n "$name" ] && printf "    name: '%s',\n" "${name//\'/\\\'}"
    [ -n "$homepage" ] && printf "    homepage: '%s',\n" "$homepage"
    [ "$archived" = true ] && printf '    archived: true,\n'
    printf '  },\n'
  } >> "$tmp"
done <<<"$repos"

printf '}\n' >> "$tmp"
mv "$tmp" "$out"

echo "wrote ${out}: ${answered}/${total} upstream repositories answered"
[ -n "$unanswered" ] && echo "::error::upstream repository does not exist (correct it in catalog/annotations.libsonnet): ${unanswered}"
[ -n "$unasked" ] && echo "forge does not report licences, so these carry only what an annotation states: ${unasked}"
[ -n "$kept" ] && echo "::error::forge unreachable, kept the previous answer for: ${kept}"
exit 0
