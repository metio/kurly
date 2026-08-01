#!/usr/bin/env bash
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Generates catalog/signatures.gen.libsonnet: whether each stage's pinned image
# carries a valid sigstore signature, and WHO signed it. A portal shows a supply
# chain marker beside a workload; the marker is only worth showing if it says
# more than "a signature exists", so this records the signer's identity and the
# repository its certificate names, and catalog.jsonnet compares that repository
# against the `upstream` kurly already publishes for the workload. "Signed by the
# project's own repository" is a fact a consumer can act on. "Signed" alone is
# not: `cosign verify` without an expected identity accepts a signature by
# anybody at all, including whoever pushed the image.
#
# WHAT IS MEASURED, exactly:
#   signed: true   the signature verifies — it covers this digest, and its
#                  certificate chains to the sigstore root and appears in the
#                  transparency log. Carries identity/issuer/sourceRepository.
#   signed: false  asked, and the registry has no signature for this digest.
#   absent         nobody asked, or the registry would not answer. NEVER read as
#                  unsigned — an entry is written only when the answer is known.
#
# The known blind spot: only KEYLESS (certificate) signatures are measured. An
# image signed with a long-lived cosign key verifies only against that key, and
# there is no discoverable way to learn which key an arbitrary publisher used —
# so a key-signed image reads `signed: false` here. That is a false negative and
# it is deliberate: the alternative is trusting a key the image itself hands us,
# which proves nothing. A workload in that position can state the truth by hand.
#
# Hits the network (two registry round trips per stage), so it is run on demand
# or on a schedule, never in the per-PR gate.
set -uo pipefail

out=catalog/signatures.gen.libsonnet

# STAGES (space-separated `<workload>/<stage>` keys) narrows the sweep, keeping
# what the last run derived for the rest — the way to re-ask the handful a rate
# limit refused without paying for the three hundred it answered.
ONLY="${STAGES:-}"
export ONLY

# What the last run derived, so an unreachable registry keeps its answer instead
# of retracting it. A retracted signature claim reads as "this image lost its
# signature", which is a security story about somebody else's project that a rate
# limit has no business telling.
PREVIOUS="$(mktemp)"
export PREVIOUS
trap 'rm -f "$PREVIOUS"' EXIT
if [ -f "$out" ]; then jsonnet "$out" 2>/dev/null >"$PREVIOUS" || echo '{}' >"$PREVIOUS"; else echo '{}' >"$PREVIOUS"; fi

# Emits a previously derived entry verbatim, for a stage this run did not ask
# about or could not reach.
keep_previous() {
  local key="$1" kept
  kept="$(jq --compact-output --arg key "$key" '.[$key] // empty' "$PREVIOUS" 2>/dev/null || true)"
  [ -n "$kept" ] || return 1
  # JSON to Jsonnet: unquote the keys, single-quote the values.
  printf '  "%s": %s,\n' "$key" \
    "$(printf '%s' "$kept" | sed -E 's/"(digest|signed|identity|issuer|sourceRepository)":/\1:/g; s/"/'"'"'/g; s/'"'"'(true|false)'"'"'/\1/g')"
}
export -f keep_previous

# The signer, read from the signature's own certificate. Sigstore records it in
# X.509 extensions under the 1.3.6.1.4.1.57264 arc: .1.1 is the OIDC issuer and
# .1.12 the source repository URI, which is the one worth comparing against
# `upstream` because it names the REPOSITORY rather than the workflow file
# inside it. The subjectAltName carries the full workflow identity — the value
# `cosign verify --certificate-identity` would be given to make this check
# reproducible by hand, so it is published rather than merely used.
#
# openssl prints the newer extensions with their DER string header intact
# (a UTF8String tag and length byte before the text), hence pulling the URL out
# by pattern rather than taking the line whole.
signer_of() {
  local ref="$1" der bundle
  bundle="$(cosign download signature "$ref" 2>/dev/null | head -1)"
  [ -n "$bundle" ] || return 1
  der="$(mktemp)"
  # Three shapes, all in the wild across the catalogue: the sigstore bundle a
  # current cosign writes, the Go certificate struct an older one wrote (base64
  # DER under .Cert.Raw), and an older one still that wrote a PEM string there.
  local b64
  b64="$(printf '%s' "$bundle" | jq -r '
    .verificationMaterial.certificate.rawBytes
    // .verificationMaterial.x509CertificateChain.certificates[0].rawBytes
    // (.Cert | if type == "object" then .Raw else empty end)
    // empty')"
  if [ -n "$b64" ]; then
    printf '%s' "$b64" | base64 -d >"$der" 2>/dev/null
  else
    printf '%s' "$bundle" | jq -r 'select(.Cert | type == "string") | .Cert' |
      openssl x509 -outform DER >"$der" 2>/dev/null
  fi
  [ -s "$der" ] || {
    rm -f "$der"
    return 1
  }

  local text identity issuer repo
  text="$(openssl x509 -inform DER -in "$der" -noout -text 2>/dev/null)"
  rm -f "$der"
  # A workflow signs under a URI; a service account signs under an email. The
  # kubernetes release process is the second kind (krel-trust@… via Google), and
  # reading only URIs dropped it on the floor as if it were unsigned.
  identity="$(printf '%s' "$text" | grep -ao 'URI:[^,[:space:]]*' | head -1 | cut -c5-)"
  [ -n "$identity" ] || identity="$(printf '%s' "$text" | grep -ao 'email:[^,[:space:]]*' | head -1 | cut -c7-)"
  issuer="$(printf '%s' "$text" | grep -a -A1 '1\.3\.6\.1\.4\.1\.57264\.1\.1:' | tail -1 | grep -ao 'https\?://[^[:space:]]*' | head -1)"
  repo="$(printf '%s' "$text" | grep -a -A1 '1\.3\.6\.1\.4\.1\.57264\.1\.12:' | tail -1 | grep -ao 'https\?://[^[:space:]]*' | head -1)"
  # Every keyless signature has a subjectAltName; the rest may be absent on a
  # non-GitHub issuer, and absent is what they then are.
  [ -n "$identity" ] || return 1
  # A workflow identity contains the repository it lives in, so a signer whose
  # certificate predates the source-repository extension is still placeable. An
  # identity that is not a URL names no repository at all — a service account is
  # a signer, not a place — and stays unplaceable rather than being parsed into
  # something that looks like one.
  if [ -z "$repo" ] || [ "$repo" = "$identity" ]; then
    case "$identity" in
      *"/.github/"*) repo="${identity%%/.github/*}" ;;
      *) repo="" ;;
    esac
  fi
  printf '%s\t%s\t%s\n' "$identity" "$issuer" "$repo"
}
export -f signer_of

# One stage: workloads/<w>/<stage>.image -> "<w>/<stage>": { ... }.
inspect_one() {
  local img="$1" key ref digest err fields identity issuer repo
  key="$(printf '%s' "$img" | sed -E 's#workloads/([^/]+)/([^/]+)\.image#\1/\2#')"
  ref="$(cat "$img")"
  if [ -n "${ONLY:-}" ] && ! grep -qw -- "$key" <<<"$ONLY"; then
    keep_previous "$key"
    return 0
  fi
  # The digest this answer is about. catalog.jsonnet publishes the claim only
  # while it still matches the stage's pin, so an image bump retracts the claim
  # rather than carrying it forward onto bits nobody measured — a signature is a
  # statement about specific bytes and means nothing detached from them.
  digest="${ref##*@}"
  case "$digest" in sha256:*) ;; *) digest="" ;; esac

  err="$(mktemp)"
  if cosign verify --certificate-identity-regexp '.*' --certificate-oidc-issuer-regexp '.*' \
    --output json "$ref" >/dev/null 2>"$err"; then
    rm -f "$err"
    fields="$(signer_of "$ref")" || fields=""
    IFS=$'\t' read -r identity issuer repo <<<"$fields"
    {
      printf '  "%s": { digest: '"'"'%s'"'"', signed: true' "$key" "$digest"
      [ -z "$identity" ] || printf ", identity: '%s'" "$identity"
      [ -z "$issuer" ] || printf ", issuer: '%s'" "$issuer"
      [ -z "$repo" ] || printf ", sourceRepository: '%s'" "$repo"
      printf ' },\n'
    }
    return 0
  fi

  # Asked and answered: the registry has no signature for this digest. Any other
  # failure — a rate limit, an unauthorized pull, a name that no longer resolves
  # — is NOT an answer, and writing `signed: false` for it would publish a
  # supply chain claim derived from a 429.
  if grep -qi 'no signatures found\|no matching signatures' "$err"; then
    rm -f "$err"
    printf '  "%s": { digest: '"'"'%s'"'"', signed: false },\n' "$key" "$digest"
    return 0
  fi
  printf '::warning::%s: could not ask (%s)\n' "$key" "$(tr -d '\n' <"$err" | head -c 120)" >&2
  rm -f "$err"
  keep_previous "$key" || printf '::warning::%s: nothing derived before either\n' "$key" >&2
}
export -f inspect_one

# Assembled from parts so REUSE does not scan this generator as carrying a
# second licence declaration of its own.
spdx_copyright='SPDX-FileCopyrightText'
spdx_license='SPDX-License-Identifier'

{
  printf '// %s: The kurly Authors\n' "$spdx_copyright"
  printf '// %s: 0BSD\n' "$spdx_license"
  echo "//"
  echo "// Generated by gen-signatures — DO NOT EDIT. Whether each stage's pinned image"
  echo "// carries a verifiable sigstore signature, and who signed it. An entry is"
  echo "// written only when the answer is known: absent means nobody asked, never"
  echo "// unsigned. The digest says which bits were measured — catalog.jsonnet drops"
  echo "// the claim once the stage's pin moves past it."
  echo "{"
  # Four at a time: the sweep makes two registry calls per stage across three
  # hundred stages, and docker.io rate-limits an anonymous puller long before
  # bandwidth is the constraint.
  git ls-files 'workloads/*/*.image' | xargs -P4 -I{} bash -c 'inspect_one "$@"' _ {} | LC_ALL=C sort
  echo "}"
} >"$out"

jsonnetfmt --in-place "$out"

echo "wrote $out ($(grep -c 'signed: true' "$out") signed, $(grep -c 'signed: false' "$out") unsigned, $(grep -c ': {' "$out") measured)"
