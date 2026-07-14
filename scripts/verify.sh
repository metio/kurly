# SPDX-FileCopyrightText: The kurly Authors
# SPDX-License-Identifier: 0BSD

# Run every gate the PR pipeline runs, in one shot, for a local pre-push check.
# CI runs these as parallel jobs for granular failure attribution; this is the
# serial local equivalent. Keep it in step with verify.yml's jobs.
check-fmt
check-tests
check-examples
check-security
reuse lint
yamllint .
actionlint
markdownlint-cli2 "**/*.md" "#vendor"
typos
echo "all gates passed"
