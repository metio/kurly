#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Trademark-policy discovery, second pass.
#
# The first pass guessed URL paths under each homepage and guessed filenames in
# each repository. It found four. This one asks instead of guessing:
#
#   1. fetch the homepage and FOLLOW the links it already carries whose href or
#      text mentions trademark/brand/legal — a project that has a policy nearly
#      always links it from the footer, and no path list predicts where it lives
#      (/legal/trademarks, /about/brand, /foundation/marks, /policies/…).
#   2. ask the forge's API for the repository's actual file list and take any
#      TRADEMARK/BRAND file that IS there, rather than probing four names.
#   3. read the README for an ownership sentence ("X is a registered trademark
#      of Y"), which does not give a posture but names WHO to ask.
#
# Emits one JSON line per workload to $OUT so a killed run keeps what it found.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
CAT=.build/catalog.json
OUT="${OUT:-./trademark-hits.jsonl}"
UA='kurly-catalog-trademark-survey/1 (+https://github.com/metio/kurly)'

get() { curl -sL --max-time 15 -A "$UA" "$1" 2>/dev/null; }

# Absolute URL from a possibly-relative href.
absolute() {
  local base="$1" href="$2"
  case "$href" in
    http*) printf '%s' "$href" ;;
    //*) printf 'https:%s' "$href" ;;
    /*) printf '%s%s' "${base%/}" "$href" ;;
    *) printf '%s/%s' "${base%/}" "$href" ;;
  esac
}

# Does this page actually discuss trademark PERMISSION, rather than merely carry
# the word in a footer? Several mentions plus language about what is allowed.
reads_like_policy() {
  local body="$1" n
  n=$(grep -ciE 'trademark|trade mark' <<<"$body")
  [ "${n:-0}" -ge 4 ] || return 1
  grep -qiE 'may not|must not|permission|prior written|our marks|use of the .{0,20}(name|mark)|guidelines' <<<"$body" || return 1
  return 0
}

probe_one() {
  local id="$1" home="$2" repo="$3"
  local found_url="" found_via="" owner_line=""

  # 1. links the homepage already carries
  if [ -n "$home" ]; then
    local page; page="$(get "$home")"
    if [ -n "$page" ]; then
      local hrefs
      hrefs=$(grep -oiE 'href="[^"]+"' <<<"$page" | sed 's/href="//I;s/"$//' \
             | grep -iE 'trademark|trade-mark|brand|marks|legal' | head -8)
      local h u body
      for h in $hrefs; do
        u="$(absolute "$home" "$h")"
        body="$(get "$u")"
        if [ -n "$body" ] && reads_like_policy "$body"; then
          found_url="$u"; found_via="homepage-link"; break
        fi
      done
    fi
  fi

  # 2. the repository's real file list
  if [ -z "$found_url" ] && [[ "$repo" == https://github.com/* ]]; then
    local slug="${repo#https://github.com/}"; slug="${slug%/}"
    local listing; listing="$(get "https://api.github.com/repos/${slug}/contents")"
    local name
    for name in $(printf '%s' "$listing" | jq -r '.[]?.name // empty' 2>/dev/null \
                  | grep -iE '^(trademark|trademarks|brand|branding)' | head -3); do
      local raw
      for br in main master; do
        raw="$(get "https://raw.githubusercontent.com/${slug}/${br}/${name}")"
        [ -n "$raw" ] && { found_url="${repo}/blob/${br}/${name}"; found_via="repo-file"; break 2; }
      done
    done
  fi

  # 3. an ownership sentence in the README — not a posture, but names the holder
  if [[ "$repo" == https://github.com/* ]]; then
    local slug="${repo#https://github.com/}"; slug="${slug%/}"
    local readme
    readme="$(get "https://api.github.com/repos/${slug}/readme" | jq -r '.content // empty' 2>/dev/null | base64 -d 2>/dev/null)"
    owner_line="$(grep -oiE '[^.]{0,90}(is a |are )?(registered )?trademarks? of [^.]{0,60}' <<<"$readme" | head -1 | tr -s ' ' | cut -c1-180)"
  fi

  jq -nc --arg id "$id" --arg url "$found_url" --arg via "$found_via" --arg owner "$owner_line" \
    '{id:$id, policy:(if $url=="" then null else $url end), via:(if $via=="" then null else $via end), ownership:(if $owner=="" then null else $owner end)}'
}

: > "$OUT"
jq -r '.workloads[] | [.id, (.upstream.homepage // ""), (.upstream.repo // "")] | @tsv' "$CAT" \
| while IFS=$'\t' read -r id home repo; do
    probe_one "$id" "$home" "$repo" >> "$OUT"
  done
echo "probe complete: $(wc -l < "$OUT") workloads, $(grep -c '"policy":"' "$OUT" || true) with a policy page"
