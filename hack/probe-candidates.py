#!/usr/bin/env python3
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

"""Rank triaged candidates by how likely they are to be carried, and cheaply.

triage-awesome-selfhosted.py decides what can be rejected from data alone. What
is left is a thousand entries in star order, and stars predict almost nothing
about whether a project can be carried: the two questions that actually decide it
are whether the project supports Kubernetes and whether it sells or gives away
its own hosting.

Both are askable without a person, and asking is much cheaper than authoring a
stage and discovering the answer:

  * KUBERNETES — a published Helm chart on ArtifactHub. A project that ships one
    has decided Kubernetes is a supported target, which is most of what makes a
    stage straightforward: an image that takes its configuration from the
    environment, a documented port, a health endpoint. A project with only a
    docker-compose.yml usually has none of that settled, and the stage becomes an
    exercise in inferring what the compose file assumed.

  * HOSTING — the project's own site offering a hosted plan, free or paid. Both
    are exclusions and for different reasons: `upstream-sells-hosting` because
    carrying it competes with the people who wrote it, `upstream-hosts-it-free`
    because nobody can compete with free. This looks for the TELLS (a pricing
    page, a "cloud" or "get started free" link) rather than deciding — the
    decision needs somebody to read the page, and the point here is to put the
    likely ones in front of them rather than to answer for them.

Neither answer is authoritative and neither is recorded in the catalogue. This
writes a WORKLIST: what to look at first, and what to look for when you do.

    probe-candidates.py <worklist.json> [--limit N] [--out ranked.json]
"""

import argparse
import concurrent.futures
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

UA = 'kurly-candidate-probe (+https://github.com/metio/kurly)'
TIMEOUT = 12

# Words a hosted offering puts on its own front page. Deliberately broad: this
# decides nothing, and a false positive costs one person one page-read, while a
# false negative costs authoring a stage for software that is given away hosted.
HOSTING_TELLS = re.compile(
    r'\b(pricing|free plan|free tier|start free|get started free|'
    r'cloud (?:hosting|version|edition)|hosted (?:version|plan|cloud)|'
    r'managed (?:hosting|cloud|instance)|sign ?up free|try (?:it )?free)\b',
    re.IGNORECASE,
)


def fetch(url):
    """The page, or None. Every failure is the same answer here — not asked."""
    try:
        req = urllib.request.Request(url, headers={'User-Agent': UA})
        with urllib.request.urlopen(req, timeout=TIMEOUT) as fh:
            return fh.read(400_000).decode('utf-8', 'replace')
    except (urllib.error.URLError, urllib.error.HTTPError, OSError, ValueError):
        return None


def has_helm_chart(name, slug):
    """Whether ArtifactHub knows a Helm chart for this project.

    Matched on the chart's own name rather than on the search ranking, because
    the search is fuzzy enough to answer "yes" for almost anything: querying
    `neko` returns charts whose description merely mentions it. A chart named for
    the project is the claim worth acting on.
    """
    q = urllib.parse.quote(name)
    body = fetch(f'https://artifacthub.io/api/v1/packages/search?kind=0&limit=20&ts_query_web={q}')
    if not body:
        return None
    try:
        packages = json.loads(body).get('packages', [])
    except json.JSONDecodeError:
        return None
    wanted = {slug.lower(), name.lower().replace(' ', '-'), name.lower().replace(' ', '')}
    for pkg in packages:
        if (pkg.get('name') or '').lower() in wanted:
            return True
    return False


def hosting_tells(website):
    """Phrases on the project's own site that suggest it offers hosting."""
    if not website:
        return []
    body = fetch(website)
    if not body:
        return []
    return sorted({m.group(0).lower() for m in HOSTING_TELLS.finditer(body)})[:5]


def probe(entry):
    name, slug = entry['name'], entry['slug']
    return {
        **entry,
        'helm': has_helm_chart(name, slug),
        'hostingTells': hosting_tells(entry.get('website')),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('worklist')
    ap.add_argument('--limit', type=int, default=200)
    ap.add_argument('--out', default='-')
    args = ap.parse_args()

    with open(args.worklist, encoding='utf-8') as fh:
        data = json.load(fh)

    # Only candidates that publish a container image: a stage pins an image, and
    # building one here would make kurly the publisher of software it does not
    # maintain.
    live = [e for e in data['live'] if not e.get('no_docker_platform')]
    live.sort(key=lambda e: -e.get('stars', 0))
    live = live[: args.limit]

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        probed = list(pool.map(probe, live))

    # A chart first, then stars. Stars break ties; they never outrank the one
    # signal that says the project targets Kubernetes at all.
    probed.sort(key=lambda e: (e['helm'] is not True, -e.get('stars', 0)))

    ready = [e for e in probed if e['helm'] is True and not e['hostingTells']]
    check = [e for e in probed if e['helm'] is True and e['hostingTells']]

    out = {'probed': probed, 'readyCount': len(ready), 'needsHostingRead': len(check)}
    text = json.dumps(out, indent=1)
    if args.out == '-':
        print(text)
    else:
        with open(args.out, 'w', encoding='utf-8') as fh:
            fh.write(text)

    print(f'probed {len(probed)} candidates', file=sys.stderr)
    print(f'  helm chart, no hosting tells : {len(ready)}', file=sys.stderr)
    print(f'  helm chart, hosting to read  : {len(check)}', file=sys.stderr)
    print(f'  no helm chart                : {sum(1 for e in probed if e["helm"] is not True)}', file=sys.stderr)
    print('\ntop of the ranked worklist:', file=sys.stderr)
    for e in ready[:25]:
        print(f'    {e["stars"]:>7}  {e["slug"]:<28} {"/".join(e["licenses"])}', file=sys.stderr)


if __name__ == '__main__':
    main()
