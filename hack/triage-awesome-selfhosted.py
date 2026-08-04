#!/usr/bin/env python3
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

"""Bulk triage of awesome-selfhosted against what kurly already knows.

The checklist's first step is to reject early, because everything after it is
expensive: authoring a stage, pinning an image, booting it on a cluster. Run over
a thousand candidates by hand and the rejections cost more than the carries.

So this applies the gates that can be decided from data alone — a licence that
forbids offering the software as a service, an archived upstream, no published
source, no container image — and leaves exactly one gate for a person, because it
cannot be read off a repository: whether the project sells its own hosting. That
one needs the pricing page, and reading it is a judgement call.

    triage-awesome-selfhosted.py <path-to-awesome-selfhosted-data> [--json out]

It DECIDES nothing. It writes a ranked worklist and says which gate each candidate
still has to pass, so a batch can be picked off the top rather than assembled by
hand every time.
"""

import json
import os
import re
import subprocess
import sys

import yaml

# Licences that forbid, or are widely read to forbid, offering the software as a
# service — the `licence-forbids-saas` reason. Matched case-insensitively against
# each declared licence, as a substring, because the data spells them
# inconsistently (`BUSL-1.1`, `BSL-1.1`, `Business Source License`).
SAAS_HOSTILE = [
    'busl', 'bsl-1.1', 'business source',
    'sspl', 'server side public',
    'elastic-2', 'elastic license',
    'commons clause',
    'proprietary', 'unfree',
    'cc-by-nc', 'cc-by-nd',
    'fsl-', 'functional source',
    'polyform',
    'redis source available', 'rsalv',
    'confluent',
]

# A licence the SPDX register knows and that permits commercial hosting is not
# enough on its own to be interesting; these are the ones worth carrying.
def licence_verdict(licenses):
    if not licenses:
        return 'no-licence-stated'
    for lic in licenses:
        # Punctuation is flattened on BOTH sides before matching. The data spells
        # the same licence `Commons-Clause`, `Commons Clause` and `CommonsClause`
        # depending on who added the entry, and a plain substring match against one
        # spelling silently PASSES the others — which is how Dify.ai, whose licence
        # is Apache-2.0 plus Commons Clause, came out top of the worklist on the
        # first run of this script.
        low = re.sub(r'[^a-z0-9]+', ' ', str(lic).lower()).strip()
        for bad in SAAS_HOSTILE:
            if re.sub(r'[^a-z0-9]+', ' ', bad).strip() in low:
                return 'licence-forbids-saas'
    return None


# awesome-selfhosted distinguishes the free edition in the NAME — "Hoppscotch
# Community Edition", "Onyx Community Edition", "AFFiNE Community Edition" — while
# this catalogue calls the same software by its plain name. Comparing the two
# unstripped reports software already excluded here as a fresh candidate.
EDITION_SUFFIX = re.compile(
    r'\s*\b(community|open[\s-]?source|free|self[\s-]?hosted)?\s*'
    r'\b(edition|ce|oss|server)\b\s*$',
    re.IGNORECASE,
)


def name_variants(name):
    """The name as given, and with a trailing edition qualifier removed."""
    raw = str(name).strip()
    out = {normalise(raw)}
    stripped = EDITION_SUFFIX.sub('', raw).strip()
    if stripped and stripped != raw:
        out.add(normalise(stripped))
    return {v for v in out if v}


def normalise(name):
    return re.sub(r'[^a-z0-9]', '', str(name).lower())


def canonical_repo(url):
    """A repository URL reduced to `host/owner/name`, so two spellings of the same
    repository compare equal — trailing slashes, `.git`, `www.`, and the scheme all
    vary between the two lists and none of them changes which repository it is."""
    if not url:
        return ''
    u = str(url).strip().lower()
    u = re.sub(r'^https?://', '', u)
    u = re.sub(r'^www\.', '', u)
    u = re.sub(r'\.git$', '', u)
    u = u.rstrip('/')
    parts = u.split('/')
    return '/'.join(parts[:3]) if len(parts) >= 3 else u


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    data_dir = os.path.join(sys.argv[1], 'software')
    if not os.path.isdir(data_dir):
        sys.exit(f'no software/ directory under {sys.argv[1]}')

    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    with open(os.path.join(repo, 'catalog', 'catalog.json'), encoding='utf-8') as fh:
        catalog = json.load(fh)
    known = {normalise(w['id']) for w in catalog['workloads']}
    known |= {normalise(k) for k in catalog.get('excluded', {})}
    # The display names too: awesome-selfhosted calls it "Forgejo" where the
    # catalogue's id is `forgejo`, but also "Home Assistant" where the id is
    # `home-assistant`, and normalising both sides is what makes those meet.
    known |= {normalise(w.get('name', '')) for w in catalog['workloads'] if w.get('name')}

    # Names alone are not enough, and the gap is not marginal. awesome-selfhosted
    # files this catalogue's `homepage` as "Homepage by gethomepage" and its
    # `actualbudget` as "Actual" — neither normalises onto the id, so both came
    # back as fresh candidates. The repository URL is the identity that actually
    # holds across the two lists, so it is matched as well.
    known_repos = set()
    for w in catalog['workloads']:
        for url in (w.get('upstream', {}).get('repo'), w.get('image', {}).get('source')):
            if url:
                known_repos.add(canonical_repo(url))
    known_repos.discard('')

    entries = []
    for fname in sorted(os.listdir(data_dir)):
        if not fname.endswith('.yml'):
            continue
        with open(os.path.join(data_dir, fname), encoding='utf-8') as fh:
            try:
                entry = yaml.safe_load(fh)
            except yaml.YAMLError:
                continue
        if not isinstance(entry, dict):
            continue
        entry['_file'] = fname
        entries.append(entry)

    rows = []
    for e in entries:
        name = e.get('name', e['_file'][:-4])
        if (name_variants(name) | name_variants(e['_file'][:-4])) & known:
            continue
        if canonical_repo(e.get('source_code_url')) in known_repos:
            continue
        if canonical_repo(e.get('website_url')) in known_repos:
            continue

        reasons = []
        if e.get('archived'):
            reasons.append('upstream-archived')
        lic = licence_verdict(e.get('licenses'))
        if lic:
            reasons.append(lic)
        if not e.get('source_code_url'):
            reasons.append('no-published-source')
        platforms = [str(p).lower() for p in (e.get('platforms') or [])]
        # No Docker platform is NOT a rejection — plenty of projects publish an
        # image without saying so here — but it is the strongest signal that the
        # first checklist step (does an image exist?) will fail, so it is surfaced
        # rather than acted on.
        no_docker = 'docker' not in platforms

        rows.append({
            'name': name,
            'slug': e['_file'][:-4],
            'licenses': e.get('licenses') or [],
            'source': e.get('source_code_url') or e.get('website_url') or '',
            'website': e.get('website_url') or '',
            'description': (e.get('description') or '').strip(),
            'stars': e.get('stargazers_count') or 0,
            'updated': str(e.get('updated_at') or ''),
            'tags': e.get('tags') or [],
            'auto_reject': reasons,
            'no_docker_platform': no_docker,
        })

    # Most-starred first among the ones still in play: a batch worked from the top
    # is a batch of software people actually run.
    live = [r for r in rows if not r['auto_reject']]
    dead = [r for r in rows if r['auto_reject']]
    live.sort(key=lambda r: -r['stars'])
    dead.sort(key=lambda r: -r['stars'])

    out = {
        'candidates': len(rows),
        'auto_rejected': len(dead),
        'needs_hosting_check': len(live),
        'live': live,
        'rejected': dead,
    }

    dest = None
    if '--json' in sys.argv:
        dest = sys.argv[sys.argv.index('--json') + 1]
        with open(dest, 'w', encoding='utf-8') as fh:
            json.dump(out, fh, indent=2)

    print(f'awesome-selfhosted entries considered : {len(entries)}')
    print(f'already carried or excluded by kurly  : {len(entries) - len(rows)}')
    print(f'candidates                            : {len(rows)}')
    print(f'  rejected on data alone              : {len(dead)}')
    by_reason = {}
    for r in dead:
        for reason in r['auto_reject']:
            by_reason[reason] = by_reason.get(reason, 0) + 1
    for reason, count in sorted(by_reason.items(), key=lambda kv: -kv[1]):
        print(f'      {reason:<24} {count}')
    print(f'  still in play                       : {len(live)}')
    print(f'      of those, no Docker platform    : {sum(1 for r in live if r["no_docker_platform"])}')
    if dest:
        print(f'wrote {dest}')
    print()
    print('top of the worklist (stars, name, licence):')
    for r in live[:20]:
        print(f'  {r["stars"]:>7}  {r["name"]:<28} {",".join(r["licenses"])[:28]}')


if __name__ == '__main__':
    main()
