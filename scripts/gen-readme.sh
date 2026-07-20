# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Splice the generated maturity badge and JaaS/stageset deploy walkthrough into
# every workload README, from the machine-readable catalog (catalog/readme.jsonnet).
# The generated section is delimited by markers and lives at the end of each
# README; the hand-written prose above it is left untouched.
#
# With KURLY_README_CHECK=1 the script checks instead of writing: it fails if any
# committed README's generated section is stale (this is the check-readme gate).
#
# tik is the hand-authored exemplar the generator is modelled on; it is left as-is.

set -euo pipefail

# The per-workload markdown sections. catalog/readme.jsonnet imports catalog.json
# directly, so no vendoring is needed here. Passed to python by path — the JSON is
# far larger than ARG_MAX.
sections_file="$(mktemp)"
trap 'rm -f "$sections_file"' EXIT
jsonnet catalog/readme.jsonnet >"$sections_file"

python3 - "$sections_file" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    sections = json.load(fh)
check = __import__("os").environ.get("KURLY_README_CHECK") == "1"

BEGIN = "<!-- BEGIN generated: jaas-deploy -->"
END = "<!-- END generated: jaas-deploy -->"
SKIP = {"tik"}  # the hand-authored exemplar

stale = []
for name, section in sorted(sections.items()):
    if name in SKIP:
        continue
    path = f"workloads/{name}/README.md"
    with open(path, encoding="utf-8") as fh:
        original = fh.read()

    # Drop any prior generated block and any hand-written JaaS section, then append
    # a fresh block — so the result is the same wherever the README started from.
    body = re.sub(re.escape(BEGIN) + r".*?" + re.escape(END), "", original, flags=re.S)
    body = re.sub(r"\n## Deploy through JaaS and stageset\b.*?(?=\n## |\Z)", "", body, flags=re.S)

    block = f"{BEGIN}\n\n{section.strip()}\n\n{END}"
    new = body.rstrip() + "\n\n" + block + "\n"

    if new == original:
        continue
    if check:
        stale.append(name)
    else:
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(new)

if check and stale:
    print("stale generated README sections (run: gen-readme):", file=sys.stderr)
    for n in stale:
        print(f"  workloads/{n}/README.md", file=sys.stderr)
    sys.exit(1)

print(("checked" if check else "wrote") + f" {len(sections) - len(SKIP)} workload READMEs")
PY
