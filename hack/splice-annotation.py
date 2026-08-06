#!/usr/bin/env python3
# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

"""Splices an authored annotation fragment into catalog/annotations.libsonnet.

    splice-annotation.py <slug> [<slug> ...] --from <dir>

Onboarding several workloads at once means several agents producing annotation
blocks, and they cannot all edit annotations.libsonnet: whoever writes last wins
and the others vanish. So each writes a FRAGMENT — its own entry, alone, in a
file named for the workload — and this splices them in one at a time.

The insertion point is the entry that sorts after it, which has one edge case
worth writing code for rather than rediscovering: a slug that sorts AFTER every
existing entry has no such entry. Treated naively that reads as "insert at the
end of the file", and the block lands outside the object it belongs to — past
the closing brace, where jsonnet reports a syntax error pointing at the entry
rather than at the placement. `zot-oci-registry` did exactly that. So the
fallback is the last entry's own closing line, never the end of the file.

Nothing here formats: jsonnetfmt is run afterwards and decides quoting and
indentation, so a fragment only has to parse.
"""

import argparse
import pathlib
import re
import sys

ANNOTATIONS = pathlib.Path('catalog/annotations.libsonnet')
# A workload entry opens at exactly four spaces of indent. Anything deeper is a
# stage or a parameter and must never be mistaken for an insertion point.
ENTRY = re.compile(r"^    '?([a-z0-9][a-z0-9._-]*)'?: \{$", re.M)


def splice(text, slug, fragment):
    if re.search(rf"^    '?{re.escape(slug)}'?: \{{$", text, re.M):
        return text, 'already annotated'

    entries = [(m.start(), m.group(1)) for m in ENTRY.finditer(text)]
    if not entries:
        raise SystemExit('no workload entries found — is this annotations.libsonnet?')

    after = next((pos for pos, key in entries if key > slug), None)
    if after is None:
        # Sorts last. Insert after the final entry's closing line, which is the
        # last "    }," in the file — NOT at the end of the file, which is
        # outside the object entirely.
        last = text.rindex('\n    },\n') + len('\n    },\n')
        return text[:last] + fragment + text[last:], 'appended after the last entry'
    return text[:after] + fragment + text[after:], 'inserted'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('slugs', nargs='+')
    ap.add_argument('--from', dest='src', required=True)
    args = ap.parse_args()

    text = ANNOTATIONS.read_text()
    for slug in args.slugs:
        frag = pathlib.Path(args.src) / f'{slug}.jsonnet'
        if not frag.is_file():
            print(f'{slug}: no fragment at {frag}', file=sys.stderr)
            continue
        text, how = splice(text, slug, frag.read_text().rstrip('\n') + '\n')
        print(f'{slug}: {how}')
    ANNOTATIONS.write_text(text)


if __name__ == '__main__':
    main()
