# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Extracts the renderable Jsonnet examples from workload READMEs into standalone
# files, so check-readme-examples can render each and validate its manifests.
# The deploy examples in a README are the code a consumer copies, so a stale one
# (a renamed feature, a wrong parameter, or a bag passed where a manifest set is
# meant) is a broken instruction — this makes the gate catch it.
#
# A README's ```jsonnet blocks share their imports: the `local … = import …`
# lines from every block are collected and prepended to each renderable one, so a
# block that names its imports in an earlier block still resolves. A block is
# "renderable" when it composes a `kurly.list(…)` — the terminal a consumer
# applies — AND is a single expression: an illustrative fragment that shows two
# separate snippets in one block (a second top-level expression starting in the
# first column, past the render) is documentation, not a program, and is skipped.
#
# Usage: extract-readme-examples.py <outdir> [README ...]
# With no README paths, every workloads/*/README.md is scanned.

import glob
import os
import re
import sys

FENCE = re.compile(r'```jsonnet\n(.*?)```', re.S)
IMPORT_LOCAL = re.compile(r'^local\s+\w+\s*=\s*import\b.*$')
# A block's prelude is its leading imports, locals, comments, and blanks; the
# expression it renders follows.
PRELUDE = re.compile(r'^(local\s|//|\s*$)')


def blocks(text):
    return FENCE.findall(text)


# A block is a single renderable program iff, past its prelude, no later line
# opens a SECOND top-level expression — a line starting in the first column with
# an identifier (a closer `)`/`]`/`}`, an operator, or indentation continues the
# one expression; `worker + …` on its own line starts another).
def single_expression(block):
    lines = block.splitlines()
    i = 0
    while i < len(lines) and PRELUDE.match(lines[i]):
        i += 1
    body = lines[i:]  # the expression, from its first line on
    for line in body[1:]:
        if line[:1].isalnum() or line[:1] == '_':
            return False
    return True


def extract(readme, outdir):
    text = open(readme).read()
    all_blocks = blocks(text)
    # Every import-local across the README, de-duplicated in first-seen order, so
    # a block resolves whether or not it repeats the imports itself.
    imports = []
    for block in all_blocks:
        for line in block.splitlines():
            if IMPORT_LOCAL.match(line) and line not in imports:
                imports.append(line)
    # workloads/tik/README.md -> tik
    workload = os.path.basename(os.path.dirname(readme))
    written = []
    n = 0
    for block in all_blocks:
        if 'kurly.list' not in block or not single_expression(block):
            continue
        n += 1
        # The block body without its own import-locals; the collected set is
        # prepended so nothing is defined twice.
        body = '\n'.join(l for l in block.splitlines() if not IMPORT_LOCAL.match(l))
        snippet = '\n'.join(imports) + '\n' + body + '\n'
        key = f'{workload}-{n}'
        path = os.path.join(outdir, f'{key}.jsonnet')
        with open(path, 'w') as f:
            f.write(snippet)
        written.append(key)
    return written


def main(argv):
    outdir = argv[1]
    readmes = argv[2:] or sorted(glob.glob('workloads/*/README.md'))
    os.makedirs(outdir, exist_ok=True)
    total = 0
    for readme in readmes:
        if not os.path.exists(readme):
            continue
        total += len(extract(readme, outdir))
    print(total)


if __name__ == '__main__':
    main(sys.argv)
